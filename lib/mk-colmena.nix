# host 에 대한 로컬/원격배포를 위해
# Host & VM 헬퍼함수를 주입받아
# Colmena Hive 선언을 도와주는 헬퍼함수
# - deployment (targetHost, targetUser, allowLocalDeployment) 는 이 파일에서 담당
# - targetUser: IaC Contract의 node.user (물리 호스트는 "limjihoon", VM은 "root")
# - allowLocalDeployment: node.hostType == "physical" 인 경우만 활성화
{
  lib,
  inputs,
  mkHost,
  mkVMs,
}:
let
  # 모든 노드(물리/VM 공통) deployment 설정
  # node.hostType 에 따라 allowLocalDeployment 자동 결정
  deploymentModule = {config, ...}: {
    deployment = {
      targetHost = config.node.ip;
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
