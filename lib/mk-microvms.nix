# MicroVM 설정 생성 함수
# homelabConstants 기반으로 microvm.vms 생성
{
  lib,
  homelabConstants,
  specialArgs,
  baseDir,
  pkgs,
}: {config, ...}: let
  hostConfig = config;
  # 전체 VM 타겟 목록
  allTargets = builtins.attrNames homelabConstants.vms;
  # 필요 시 특정 VM만 필터링
  vms =
    if specialArgs.microvmTargets == null
    then allTargets
    else builtins.filter (name: builtins.elem name specialArgs.microvmTargets) allTargets;

  # VM별 필요한 secrets 정의 (principle of least privilege)
  # sops.nix의 secret 이름과 일치해야 함 (예: "k8s/joinToken", "rootPassword")
  vmSecrets = {
    k8s-master = ["k8s/joinToken" "rootPassword"];
    k8s-worker-1 = ["k8s/joinToken" "rootPassword"];
    k8s-worker-2 = ["k8s/joinToken" "rootPassword"];
    vault = ["rootPassword"];
    jenkins = ["rootPassword"];
    registry = ["rootPassword"];
  };

  # VM에 전달할 추가 인자 확장
  vmSpecialArgs =
    specialArgs
    // {
      hostSshKeys = hostConfig.users.users.${homelabConstants.hosts.${homelabConstants.defaultHost}.username}.openssh.authorizedKeys.keys;
    };

  # VM 이름 → 설정 파일 경로 매핑
  vmConfigPath = name: baseDir + "/vms/${name}.nix";

  # VM 공통 모듈 생성: 쉘 및 사용자 비밀번호
  mkVmCommonModule = sshKey: {lib, ...}: {
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
      openssh.authorizedKeys.keys = lib.optional (sshKey != "") sshKey;
      # Password is loaded from sops secret shared via virtiofs
      hashedPasswordFile = "${specialArgs.vmSecretsPath}/rootPassword";
    };
  };

  # Secrets 공유 모듈 생성
  # secret 이름에 "/" 포함 시 tag에서 "-"로 치환 (virtiofs tag 규칙)
  mkSecretsModule = name: let
    secretsForVm = vmSecrets.${name} or [];
    vmSecretsPath = specialArgs.vmSecretsPath;
    mkTag = secret: "secret-${builtins.replaceStrings ["/"] ["-"] secret}";
    secretShares = map (secret: {
      source = "/run/secrets/${secret}";
      mountPoint = "${vmSecretsPath}/${secret}";
      tag = mkTag secret;
      proto = "virtiofs";
    }) secretsForVm;
    secretMounts = lib.listToAttrs (map (secret: {
      name = "${vmSecretsPath}/${secret}";
      value = {
        device = mkTag secret;
        fsType = "virtiofs";
        options = ["ro"];
      };
    }) secretsForVm);
  in
    lib.optionalAttrs (secretsForVm != []) {
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
              (mkVmCommonModule specialArgs.sshPublicKey)
              (mkSecretsModule name)
            ];
          };
          specialArgs = vmSpecialArgs // {microvmTarget = name;};
          autostart = true;
        });
  };
}
