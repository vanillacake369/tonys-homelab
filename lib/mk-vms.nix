# VM 구성 선언을 도와주는 헬퍼함수
# - nodes/vms/*.nix 자동 탐색 (extract-filename.nix)
# - data 의존성 없음: 각 노드 파일이 IaC Contract 값을 자체 선언
# - deployment 설정은 mk-colmena.nix 에서 담당
{
  lib,
  inputs,
}: rec {
  discoverNodes = import ./extract-filename.nix {inherit lib;};

  vmNames = discoverNodes ../nodes/vms;

  # 단일 VM 구성 함수
  # (Attribute name을 hostname으로 사용)
  mkVM = name: {
    # VM 노드 공통 설정 (노드 파일에서 override 가능)
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    networking.hostName = lib.mkDefault name;

    imports = [
      inputs.microvm.nixosModules.microvm
      inputs.sops-nix.nixosModules.sops
      ../nodes/interface.nix
      ../nodes/vms/${name}.nix
    ];
  };

  # 모든 VM 노드들을 생성하여
  # Colmena에 전달할 형태로 반환
  vmNodes = lib.genAttrs vmNames mkVM;
}
