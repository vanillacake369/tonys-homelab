# Node: k8s-master-2
{...}: let
  network = import ../../network/topology.nix;
  net = network.vms.k8s-master-2;
in {
  imports = [
    ../interface.nix
    ../roles/k8s-master.nix
  ];

  node = {
    ip = net.ip;
    mac = net.mac;
    role = "k8s-master";
    hostType = "vm";
    parentHost = "homelab-1";
  };

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  systemd.network.networks."10-eth" = {
    matchConfig.MACAddress = net.mac;
    address = ["${net.ip}/24"];
    networkConfig = {
      Gateway = network.vlans.services.gateway;
      DNS = network.dns;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  system.stateVersion = "24.11";
}
