# VM QCOW2 이미지 빌드 헬퍼
# nixos-generators로 각 VM의 nixosConfiguration을 QCOW2 이미지로 변환
# 사용: nix build .#k8s-master-1 (타겟 아키텍처에서만 빌드 가능)
{
  lib,
  inputs,
  targetSystem,
}: let
  discoverNodes = import ./extract-filename.nix {inherit lib;};
  vmNames = discoverNodes ../nodes/vms;

  mkImage = name:
    inputs.nixos-generators.nixosGenerate {
      system = targetSystem;
      format = "qcow";
      modules = [
        inputs.sops-nix.nixosModules.sops
        ../nodes/interface.nix
        ../nodes/vms/${name}.nix
      ];
      specialArgs = {inherit inputs;};
    };
in
  lib.genAttrs vmNames mkImage
