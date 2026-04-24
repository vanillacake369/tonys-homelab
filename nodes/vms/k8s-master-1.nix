# Node: k8s-master-1
{lib, ...}: let
  network = import ../../network/topology.nix;
  net = network.vms.k8s-master-1;
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

  # 표준 GRUB 부트 (libvirt QCOW2 가상 디스크)
  # mkDefault: system.build.images.qemu가 이미지 빌드 시 override
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
