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
  vmModules = [
    inputs.microvm.nixosModules.microvm
    (baseDir + "/modules/nixos/sops.nix")
    {nixpkgs.config.allowUnfree = true;}
  ];

  # 물리 호스트(서버)용 Colmena 노드 정의
  baseHive = {
    # 공통 메타 설정
    meta = {
      nixpkgs = import inputs.nixpkgs {system = mainSystem;};
      inherit specialArgs;
    };
    # 실제 서버 노드 (homelab)
    homelab = {
      deployment = with homelabConstants.host.deployment; {
        inherit targetHost targetUser;
        buildOnTarget = true;
        tags = ["physical" "homelab"];
      };
      imports = hostModules;
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
  }) (lib.filterAttrs (_: vmInfo: vmInfo.deployment.colmena or true) homelabConstants.vms);
in
  inputs.colmena.lib.makeHive (baseHive // vmHive)
