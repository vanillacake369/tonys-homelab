# Host 구성 선언을 도와주는 헬퍼함수
# - nodes/physical/*.nix 자동 탐색 (extract-filename.nix)
# - data 의존성 없음: 각 노드 파일이 IaC Contract 값을 자체 선언
# - deployment 설정은 mk-colmena.nix 에서 담당
# - nixosConfigurations 선언:
#   - disko
#   - microvm host
#   - sops-nix
#   - 실제 host 선언
{
  lib,
  inputs,
}: rec {
  discoverNodes = import ./extract-filename.nix {inherit lib;};

  hostNames = discoverNodes ../nodes/physical;

  mkHost = name: {
    # 시스템 호스트명과 아키텍처 지정 (노드 파일에서 override 가능)
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    networking.hostName = lib.mkDefault name;

    # IaC Contract 에 따르는
    # Host 패키지 주입
    imports = [
      inputs.disko.nixosModules.disko
      inputs.microvm.nixosModules.host
      inputs.sops-nix.nixosModules.sops
      ../nodes/interface.nix
      ../nodes/physical/${name}.nix
    ];
  };

  hostNodes = lib.genAttrs hostNames mkHost;
}
