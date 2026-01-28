# Colmena 하이브 생성 함수
# 호스트/VM 배포 구성을 묶어서 반환
{
  lib,
  inputs,
  homelabConstants,
  specialArgs,
  mainSystem,
  hostModules,
  baseDir,
}: let
  # VM 공통 모듈 묶음
  # Note: sops.nix is NOT included here - VMs receive secrets via virtiofs
  # from the host (see mk-microvms.nix mkSecretsModule)
  vmModules = [
    inputs.microvm.nixosModules.microvm
    {nixpkgs.config.allowUnfree = true;}
  ];

  # DEPLOY_TARGET 환경변수로 targetHost override 가능
  # LAN/Tailscale 동적 전환을 위해 justfile에서 주입
  deployTargetOverride = builtins.getEnv "DEPLOY_TARGET";

  # 물리 호스트 Colmena 노드 생성 (homelabConstants.hosts에서 동적 생성)
  hostHive = lib.mapAttrs (name: hostInfo: {
    deployment = {
      targetHost =
        if deployTargetOverride != ""
        then deployTargetOverride
        else hostInfo.deployment.targetHost;
      targetUser = hostInfo.deployment.targetUser;
      buildOnTarget = hostInfo.deployment.buildOnTarget or true;
      tags = hostInfo.deployment.tags or ["physical"];
    };
    imports = hostModules;
  }) homelabConstants.hosts;

  # Colmena 메타 설정
  metaHive = {
    meta = {
      nixpkgs = import inputs.nixpkgs {system = mainSystem;};
      inherit specialArgs;
    };
  };

  # VM 이름 → 설정 파일 경로 매핑
  vmConfigPath = name: baseDir + "/vms/${name}.nix";

  # VM별 Colmena 노드 구성
  vmHive = lib.mapAttrs (name: vmInfo: {
    # VM 배포 대상 및 태그 설정
    deployment = {
      targetHost = vmInfo.ip;
      targetUser = vmInfo.deployment.user;
      buildOnTarget = true;
      tags = vmInfo.deployment.tags;
    };
    imports =
      vmModules
      ++ [
        (vmConfigPath name)
        (_: {
          # VM 사용자 SSH 키 주입
          users.users.${vmInfo.deployment.user}.openssh.authorizedKeys.keys =
            lib.optional (specialArgs.sshPublicKey != "") specialArgs.sshPublicKey;

          # VM OpenSSH 호스트 키 경로 지정
          services.openssh.hostKeys = [
            {
              path = "/etc/ssh/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];
        })
      ];
  })
  # Filter VMs for Colmena deployment
  # VMs are included by default unless deployment.colmena = false
  (lib.filterAttrs (_: vmInfo: vmInfo.deployment.colmena or true) homelabConstants.vms);
in
  inputs.colmena.lib.makeHive (metaHive // hostHive // vmHive)
