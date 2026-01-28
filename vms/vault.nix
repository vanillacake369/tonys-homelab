# Vault Secret Management VM
# VLAN 10 (Management)
{
  pkgs,
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.vault;
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

    shares = [
      {
        source = vmInfo.storage.source;
        mountPoint = vmInfo.storage.mountPoint;
        tag = vmInfo.storage.tag;
        proto = "virtiofs";
      }
    ];
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

  # Vault service
  services.vault = {
    enable = true;
    address = "0.0.0.0:${toString vmInfo.ports.api}";
    storageBackend = "file";
    storagePath = vmInfo.storage.mountPoint;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = builtins.attrValues vmInfo.ports;
  };

  # Vault-specific packages
  environment.systemPackages = with pkgs; [
    vault
    curl
    jq
  ];

  system.stateVersion = homelabConstants.common.stateVersion;
}
