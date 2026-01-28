# MicroVM 설정 생성 함수
# Domain-driven architecture: uses profiles for VM configurations
{
  lib,
  homelabConstants,
  specialArgs,
  baseDir,
  pkgs,
}: {config, ...}: let
  # Import profiles for domain-based configuration
  profiles = specialArgs.profiles or (import ./profiles.nix { inherit pkgs lib; });
  domains = specialArgs.domains or profiles.domains;
  # 전체 VM 타겟 목록
  allTargets = builtins.attrNames homelabConstants.vms;
  # 필요 시 특정 VM만 필터링
  vms =
    if specialArgs.microvmTargets == null
    then allTargets
    else builtins.filter (name: builtins.elem name specialArgs.microvmTargets) allTargets;

  # 호스트 SSH 공개키 (homelab-constants.nix에서 정의)
  # VM root 사용자의 authorized_keys에 추가됨
  hostSshPubKey = homelabConstants.hosts.${homelabConstants.defaultHost}.sshPubKey or null;

  # VM별 필요한 secrets 디렉토리 정의 (principle of least privilege)
  # virtiofs는 디렉토리만 공유 가능 (파일 직접 공유 불가)
  # 각 항목은 { source, mountPoint, tag } 형태
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

  # VM에 전달할 추가 인자 확장
  vmSpecialArgs = specialArgs;

  # VM 이름 → 설정 파일 경로 매핑
  vmConfigPath = name: baseDir + "/vms/${name}.nix";

  # VM 공통 모듈 생성: 쉘, SSH 키, 사용자 비밀번호
  # Domain-driven: uses profiles based on VM type
  # 호스트의 SSH 공개키는 homelab-constants.nix에서 정의
  mkVmCommonModule = vmName: {lib, ...}: let
    # K8s VMs use k8s-node profile, others use server profile
    isK8sVm = lib.hasPrefix "k8s-" vmName;
    profileName = if isK8sVm then "k8s-node" else "server";
    vmProfile = profiles.nixos.${profileName};
    shellDomain = domains.shell;
    editorDomain = domains.editor;
  in {
    # Packages from appropriate profile
    environment.systemPackages = vmProfile.packages.environment.systemPackages;

    # Editor configuration from domain
    programs.neovim = {
      enable = editorDomain.neovim.enable;
      defaultEditor = editorDomain.neovim.defaultEditor;
    };

    # Shell configuration from domain (NixOS style)
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = shellDomain.aliases;
      interactiveShellInit = ''
        ${builtins.concatStringsSep "\n" (builtins.attrValues shellDomain.functions)}
        ${lib.optionalString pkgs.stdenv.isLinux (builtins.concatStringsSep "\n" (builtins.attrValues (shellDomain.functionsLinux or {})))}
      '';
    };

    users.users.root = {
      shell = pkgs.zsh;
      # SSH 공개키는 homelab-constants.nix에서 하드코딩된 값 사용
      openssh.authorizedKeys.keys = lib.optional (hostSshPubKey != null) hostSshPubKey;
      # Password is loaded from sops secret shared via virtiofs
      # users/ 디렉토리가 마운트되므로 users/rootPassword 경로 사용
      hashedPasswordFile = "${specialArgs.vmSecretsPath}/users/rootPassword";
    };
  };

  # Secrets 디렉토리 공유 모듈 생성
  # virtiofs는 디렉토리만 공유 가능하므로 디렉토리 단위로 마운트
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

  # VM 데이터 영구 저장 모듈 (etcd, vault, jenkins 등)
  # homelab-constants.nix의 storage 설정을 읽어 virtiofs로 마운트
  mkStorageModule = name: {lib, ...}: let
    vmInfo = homelabConstants.vms.${name};
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

  # K8s 노드 영구 저장 모듈 (kubeadm 기반)
  # /etc/kubernetes, /var/lib/etcd(master만) 영구 저장
  # 주의: /var/lib/kubelet은 virtiofs로 마운트하면 안 됨 (cAdvisor가 디바이스 정보를 찾지 못함)
  # homelab-constants.nix의 storage 설정과 중복되지 않도록 체크
  mkK8sStorageModule = name: {lib, ...}: let
    isK8sNode = lib.hasPrefix "k8s-" name;
    isMaster = name == "k8s-master";
    baseDir = "/var/lib/microvms/${name}";
    vmInfo = homelabConstants.vms.${name};
    # 기존 storage 설정이 있는지 확인 (중복 방지)
    hasExistingStorage = vmInfo ? storage;
    existingMountPoint = if hasExistingStorage then vmInfo.storage.mountPoint else "";
  in
    lib.optionalAttrs isK8sNode {
      microvm.shares = lib.mkAfter ([
        # /etc/kubernetes - 인증서, manifests, kubeconfig
        {
          source = "${baseDir}/kubernetes";
          mountPoint = "/etc/kubernetes";
          tag = "k8s-config";
          proto = "virtiofs";
        }
      ] ++ lib.optionals (isMaster && existingMountPoint != "/var/lib/etcd") [
        # /var/lib/etcd - etcd 데이터 (master만, 기존 storage와 중복되지 않는 경우)
        {
          source = "${baseDir}/etcd";
          mountPoint = "/var/lib/etcd";
          tag = "k8s-etcd";
          proto = "virtiofs";
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
  # VM 재시작 시에도 SSH 호스트 키가 유지되어 known_hosts 경고 방지
  mkSshHostKeyModule = name: {lib, ...}: let
    hostKeyDir = "/var/lib/microvms/${name}/ssh";
    vmKeyDir = "/persistent/ssh";
  in {
    # 호스트의 SSH 키 디렉토리를 VM에 공유
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

    # SSH 서비스가 영구 저장소의 호스트 키를 사용하도록 설정
    # mkForce로 NixOS 기본 hostKeys 설정을 덮어씀
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

in {
  config = {
    # MicroVM 호스트 기능 활성화
    microvm.host.enable = true;
    # 선택적 MicroVM 목록 생성
    # INFO : CI 인 경우 빈 값이 넘어오기 때문에
    # 생성처리를 하지 않습니다.
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
            ];
          };
          specialArgs = vmSpecialArgs // {microvmTarget = name;};
          autostart = true;
        });
  };
}
