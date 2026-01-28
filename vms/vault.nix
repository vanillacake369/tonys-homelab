# Vault Secret Management VM
# VLAN 10 (Management)
{
  pkgs,
  data,
  ...
}: let
  vmInfo = data.vms.definitions.vault;
  vlan = data.network.vlans.${vmInfo.vlan};
in {
  imports = [
    ../modules/nixos/vm-base.nix
  ];

  # User configuration
  # Password is managed via sops in mk-microvms.nix (mkVmCommonModule)
  users.mutableUsers = false;

  microvm = {
    hypervisor = data.hosts.common.hypervisor;
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
    nameservers = data.network.dns;
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = ["${vmInfo.ip}/${toString vlan.prefixLength}"];
    gateway = [vlan.gateway];
    dns = data.network.dns;
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

  system.stateVersion = data.hosts.common.stateVersion;
}
