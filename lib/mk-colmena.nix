# Colmena Hive 선언 헬퍼 — Host & VM 노드를 병합하고 deployment 설정 주입
#
# targetHost 전략:
#   물리 호스트: hostname 사용 (SSH config에서 LAN 또는 Tailscale IP로 명시적 지정 권장)
#   VM: LAN IP 사용 (SSH config의 ProxyJump로 물리 호스트 경유)
#
# 사전 요구: ~/.ssh/config에 물리 호스트에 대한 적절한 IP(LAN/Tailscale) 설정 필요
# 상세 설정은 README.md "Quick Start > SSH 설정" 참조
{
  lib,
  inputs,
  mkHost,
  mkVMs,
}: let
  # 모든 노드(물리/VM 공통) deployment 설정
  # node.hostType 에 따라 allowLocalDeployment 자동 결정
  deploymentModule = {config, ...}: {
    deployment = {
      # 물리 호스트: hostname (SSH config에서 LAN/Tailscale 동적 해석)
      # VM: LAN IP (ProxyJump 경유)
      targetHost =
        if config.node.hostType == "physical"
        then config.networking.hostName
        else config.node.ip;
      targetUser = config.node.user;
      buildOnTarget = true;
      allowLocalDeployment = config.node.hostType == "physical";
    };
  };

  # nodeConfig에 deployment 모듈 주입
  injectDeployment = nodeConfig: {
    imports = [nodeConfig deploymentModule];
  };
in
  inputs.colmena.lib.makeHive (
    lib.mapAttrs (_: injectDeployment) mkHost.hostNodes
    // lib.mapAttrs (_: injectDeployment) mkVMs.vmNodes
    // {
      meta = {
        # Colmena가 사용할 nixpkgs 인스턴스
        # single-platform homelab: x86_64-linux 고정
        nixpkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        # 모든 노드에 주입될 공통 인자
        specialArgs = {
          inherit inputs;
        };
      };
    }
  )
