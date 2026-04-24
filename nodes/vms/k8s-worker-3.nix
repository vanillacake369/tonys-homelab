# Node: k8s-worker-3
{lib, ...}: let
  network = import ../../network/topology.nix;
  net = network.vms.k8s-worker-3;
in {
  imports = [
    ../interface.nix
    ../roles/k8s-worker.nix
  ];

  node = {
    ip = net.ip;
    mac = net.mac;
    role = "k8s-worker";
    hostType = "vm";
    parentHost = "homelab-1";
  };

  boot.loader.grub = {
    enable = lib.mkDefault true;
    device = lib.mkDefault "/dev/vda";
  };

  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/nixos";
    fsType = lib.mkDefault "ext4";
  };

  systemd.network.networks."10-eth" = {
    matchConfig.MACAddress = net.mac;
    address = ["${net.ip}/24"];
    networkConfig = {
      Gateway = network.hosts.homelab-1.vlans.services.gateway;
      DNS = network.dns;
    };
    linkConfig.RequiredForOnline = "routable";
  };
}
