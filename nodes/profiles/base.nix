# Base profile shared by every managed homelab node.
{
  config,
  lib,
  ...
}: {
  system.stateVersion = "24.11";

  # VM nodes expand their disk partition after provisioning.
  boot.growPartition = lib.mkIf (config.node.hostType == "vm") true;

  # Virtual drivers required during VM initrd boot.
  boot.initrd.availableKernelModules = lib.mkIf (config.node.hostType == "vm") [
    "virtio_net"
    "virtio_pci"
    "virtio_mmio"
    "virtio_blk"
    "virtio_scsi"
    "9p"
    "9pnet_virtio"
  ];

  imports = [
    ../../atoms/system/sops.nix
    ../../atoms/system/nix.nix
    ../../atoms/system/locale.nix
    ../../atoms/system/timesyncd.nix
    ../../atoms/system/shell.nix
    ../../atoms/system/cli-tools.nix
    ../../atoms/user/root.nix
    ../../atoms/network/ssh-server.nix
    ../../atoms/network/network-base.nix
    ../../atoms/system/authorized-keys.nix
  ];
}
