# Container Registry VM
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.registry;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
in {
  imports = [
    ../modules/nixos/vm-base.nix
  ];

  # User configuration
  # Password is managed via sops in mk-microvms.nix (mkVmCommonModule)
  users.mutableUsers = false;

  microvm = {
    hypervisor = homelabConstants.common.hypervisor;
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;
    vsock.cid = vmInfo.vsockCid;

    interfaces = [
      {
        type = "tap";
        id = vmInfo.tapId;
        mac = vmInfo.mac;
      }
    ];

    # Storage share는 mk-microvms.nix의 mkStorageModule이 처리
    shares = [];
  };

  # Network configuration (systemd-networkd)
  networking = {
    hostName = vmInfo.hostname;
    useDHCP = false;
    nameservers = homelabConstants.networks.dns;
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = ["${vmInfo.ip}/${toString vlan.prefixLength}"];
    gateway = [vlan.gateway];
    dns = homelabConstants.networks.dns;
    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = false;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Docker Registry service
  services.dockerRegistry = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = vmInfo.ports.registry;
    storagePath = vmInfo.storage.mountPoint;
    enableDelete = true;
    enableGarbageCollect = true;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = builtins.attrValues vmInfo.ports;
  };

  # Registry-specific packages
  environment.systemPackages = with pkgs; [
    curl
    jq
    docker
  ];

  system.stateVersion = homelabConstants.common.stateVersion;
}
