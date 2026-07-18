{
  name,
  roleModule,
}: {lib, ...}: let
  network = import ../network/topology.nix;
  net = network.vms.${name};
  parent = network.hosts.${net.parentHost};
  vlan = network.vlans.${net.network};
in {
  imports = [
    ../nodes/interface.nix
    roleModule
  ];

  node = {
    inherit (net) ip mac role parentHost;
    hostType = "vm";
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
    address = ["${net.ip}/${toString vlan.prefixLength}"];
    networkConfig = {
      Gateway = parent.vlans.${net.network}.gateway;
      DNS = network.dns;
    };
    linkConfig.RequiredForOnline = "routable";
  };
}
