{pkgs, lib, data, ...}: {
  imports = [
    ../modules/profiles/vm-base.nix
    ../modules/profiles/vm-persistent.nix
    ../modules/profiles/vm-common.nix
    ../modules/profiles/k8s-node.nix
    ../modules/profiles/k8s-worker.nix
  ];
}
