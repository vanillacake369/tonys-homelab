# VM QCOW2 이미지 빌드 헬퍼
# NixOS 내장 system.build.images.qemu 사용 (nixos-generators deprecated since 25.05)
# 사용: nix build .#k8s-master-1 (타겟 아키텍처에서만 빌드 가능)
{
  lib,
  nixosConfigurations,
}: let
  # VM 노드만 필터링 (k8s-* prefix)
  vmConfigs = lib.filterAttrs (name: _: lib.hasPrefix "k8s-" name) nixosConfigurations;
in
  lib.mapAttrs (_: config: config.config.system.build.images.qemu) vmConfigs
