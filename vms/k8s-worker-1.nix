{
  pkgs,
  lib,
  data,
  ...
}: {
  imports = [
    ../modules/platform/vm/base.nix
    ../modules/platform/vm/persistent.nix
    ../modules/platform/vm/k8s-node.nix
    ../modules/platform/vm/k8s-worker.nix
  ];
}
