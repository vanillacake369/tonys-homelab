# MicroVM 설정 생성 함수
# homelabConstants 기반으로 microvm.vms 생성
{
  lib,
  homelabConstants,
  specialArgs,
  baseDir,
  pkgs,
}: {config, ...}: let
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
  # 호스트의 SSH 공개키는 homelab-constants.nix에서 정의
  mkVmCommonModule = {lib, ...}: {
    environment.systemPackages = with pkgs; [
      vim
      git
      ripgrep
      htop
      btop
      wget
      curl
      tree
      ncdu
      bat
      jq
      lsof
      psmisc
    ];
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        ll = "ls -l";
        cat = "bat --style=plain --paging=never";
        grep = "rg";
        k = "kubectl";
      };
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
              mkVmCommonModule
              (mkSecretsModule name)
            ];
          };
          specialArgs = vmSpecialArgs // {microvmTarget = name;};
          autostart = true;
        });
  };
}
