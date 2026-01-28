# MicroVM 설정 생성 함수
# data 기반 아키텍처: profiles/adapters 미들웨어 제거
{
  lib,
  data,
  specialArgs,
  baseDir,
  pkgs,
}: {config, ...}: let
  # 전체 VM 타겟 목록
  allTargets = builtins.attrNames data.vms.definitions;
  # 필요 시 특정 VM만 필터링
  vms =
    if specialArgs.microvmTargets == null
    then allTargets
    else builtins.filter (name: builtins.elem name specialArgs.microvmTargets) allTargets;

  # 호스트 SSH 공개키
  hostSshPubKey = data.hosts.definitions.${data.hosts.default}.sshPubKey or null;

  # VM 프로필별 그룹 목록
  vmProfiles = {
    k8s-node = ["core" "shell" "editor" "network" "monitoring" "k8s" "hardware"];
    server = ["core" "shell" "editor" "network" "monitoring" "dev" "hardware"];
  };

  resolvePackages = profileName:
    builtins.concatLists (
      map (g: map (name: pkgs.${name}) (data.packages.${g} or []))
        (vmProfiles.${profileName} or vmProfiles.server)
    );

  # VM별 필요한 secrets 디렉토리 정의 (principle of least privilege)
  vmSecretDirs = {
    k8s-master = [
      {source = "/run/secrets/k8s"; mountPoint = "k8s"; tag = "secrets-k8s";}
      {source = "/run/secrets-for-users"; mountPoint = "users"; tag = "secrets-users";}
    ];
    k8s-worker-1 = [
      {source = "/run/secrets/k8s"; mountPoint = "k8s"; tag = "secrets-k8s";}
      {source = "/run/secrets-for-users"; mountPoint = "users"; tag = "secrets-users";}
    ];
    k8s-worker-2 = [
      {source = "/run/secrets/k8s"; mountPoint = "k8s"; tag = "secrets-k8s";}
      {source = "/run/secrets-for-users"; mountPoint = "users"; tag = "secrets-users";}
    ];
    vault = [
      {source = "/run/secrets-for-users"; mountPoint = "users"; tag = "secrets-users";}
    ];
    jenkins = [
      {source = "/run/secrets-for-users"; mountPoint = "users"; tag = "secrets-users";}
    ];
    registry = [
      {source = "/run/secrets-for-users"; mountPoint = "users"; tag = "secrets-users";}
    ];
  };

  # VM 이름 → 설정 파일 경로 매핑
  vmConfigPath = name: baseDir + "/vms/${name}.nix";

  # VM 공통 모듈 생성: 패키지, SSH 키, 사용자 비밀번호
  # shell/editor 설정은 modules/nixos/shell.nix, editor.nix를 import하여 처리
  mkVmCommonModule = vmName: {lib, ...}: let
    isK8sVm = lib.hasPrefix "k8s-" vmName;
    profileName = if isK8sVm then "k8s-node" else "server";
  in {
    imports = [
      (baseDir + "/modules/nixos/shell.nix")
      (baseDir + "/modules/nixos/editor.nix")
    ];

    environment.systemPackages = resolvePackages profileName;

    users.users.root = {
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = lib.optional (hostSshPubKey != null) hostSshPubKey;
      hashedPasswordFile = "${specialArgs.vmSecretsPath}/users/rootPassword";
    };
  };

  # Secrets 디렉토리 공유 모듈 생성
  mkSecretsModule = name: let
    secretDirsForVm = vmSecretDirs.${name} or [];
    vmSecretsPath = specialArgs.vmSecretsPath;
    secretShares = map (dir: {
      source = dir.source;
      mountPoint = "${vmSecretsPath}/${dir.mountPoint}";
      tag = dir.tag;
      proto = "virtiofs";
    }) secretDirsForVm;
    secretMounts = lib.listToAttrs (map (dir: {
      name = "${vmSecretsPath}/${dir.mountPoint}";
      value = {
        device = dir.tag;
        fsType = "virtiofs";
        options = ["ro"];
      };
    }) secretDirsForVm);
  in
    lib.optionalAttrs (secretDirsForVm != []) {
      microvm.shares = lib.mkAfter secretShares;
      fileSystems = secretMounts;
    };

  # VM 데이터 영구 저장 모듈
  mkStorageModule = name: {lib, ...}: let
    vmInfo = data.vms.definitions.${name};
    hasStorage = vmInfo ? storage;
    storage = vmInfo.storage or {};
  in
    lib.optionalAttrs hasStorage {
      microvm.shares = lib.mkAfter [
        {
          source = storage.source;
          mountPoint = storage.mountPoint;
          tag = storage.tag;
          proto = "virtiofs";
        }
      ];

      fileSystems.${storage.mountPoint} = {
        device = storage.tag;
        fsType = "virtiofs";
        neededForBoot = true;
      };
    };

  # K8s 노드 영구 저장 모듈
  mkK8sStorageModule = name: {lib, ...}: let
    isK8sNode = lib.hasPrefix "k8s-" name;
    isMaster = name == "k8s-master";
    baseDir = "/var/lib/microvms/${name}";
    vmInfo = data.vms.definitions.${name};
    hasExistingStorage = vmInfo ? storage;
    existingMountPoint = if hasExistingStorage then vmInfo.storage.mountPoint else "";
    hasKubeletVolume = vmInfo ? kubeletVolume;
    kubeletVolume = vmInfo.kubeletVolume or {};
  in
    lib.optionalAttrs isK8sNode {
      microvm.shares = lib.mkAfter ([
        {
          source = "${baseDir}/kubernetes";
          mountPoint = "/etc/kubernetes";
          tag = "k8s-config";
          proto = "virtiofs";
        }
      ] ++ lib.optionals (isMaster && existingMountPoint != "/var/lib/etcd") [
        {
          source = "${baseDir}/etcd";
          mountPoint = "/var/lib/etcd";
          tag = "k8s-etcd";
          proto = "virtiofs";
        }
      ]);

      microvm.volumes = lib.mkIf hasKubeletVolume (lib.mkAfter [
        {
          image = "${baseDir}/kubelet.img";
          mountPoint = "/var/lib/kubelet";
          size = kubeletVolume.size or 2048;
          fsType = "ext4";
          autoCreate = true;
        }
      ]);

      fileSystems = {
        "/etc/kubernetes" = {
          device = "k8s-config";
          fsType = "virtiofs";
          neededForBoot = true;
        };
      } // lib.optionalAttrs (isMaster && existingMountPoint != "/var/lib/etcd") {
        "/var/lib/etcd" = {
          device = "k8s-etcd";
          fsType = "virtiofs";
          neededForBoot = true;
        };
      };
    };

  # SSH 호스트 키 영구 저장 모듈
  mkSshHostKeyModule = name: {lib, ...}: let
    hostKeyDir = "/var/lib/microvms/${name}/ssh";
    vmKeyDir = "/persistent/ssh";
  in {
    microvm.shares = lib.mkAfter [
      {
        source = hostKeyDir;
        mountPoint = vmKeyDir;
        tag = "ssh-host-keys";
        proto = "virtiofs";
      }
    ];

    fileSystems.${vmKeyDir} = {
      device = "ssh-host-keys";
      fsType = "virtiofs";
      neededForBoot = true;
    };

    services.openssh.hostKeys = lib.mkForce [
      {
        path = "${vmKeyDir}/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "${vmKeyDir}/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  # 홈 디렉토리 영구 저장 모듈 (.p10k.zsh, .zsh_history 등)
  mkHomeStorageModule = name: {lib, ...}: let
    baseDir = "/var/lib/microvms/${name}";
  in {
    microvm.shares = lib.mkAfter [
      {
        source = "${baseDir}/home/root";
        mountPoint = "/root";
        tag = "home-root";
        proto = "virtiofs";
      }
    ];

    fileSystems."/root" = {
      device = "home-root";
      fsType = "virtiofs";
      neededForBoot = true;
    };
  };

in {
  config = {
    # MicroVM 호스트 기능 활성화
    microvm.host.enable = true;
    # 선택적 MicroVM 목록 생성
    microvm.vms =
      if specialArgs.microvmTargets == []
      then {}
      else
        lib.genAttrs vms (name: {
          config = {
            imports = [
              (vmConfigPath name)
              (mkVmCommonModule name)
              (mkSecretsModule name)
              (mkStorageModule name)
              (mkK8sStorageModule name)
              (mkSshHostKeyModule name)
              (mkHomeStorageModule name)
            ];
          };
          specialArgs = specialArgs // {microvmTarget = name;};
          autostart = true;
        });
  };
}
