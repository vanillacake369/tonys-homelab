# Jenkins CI/CD VM
# VLAN 10 (Management)
{
  pkgs,
  data,
  ...
}: let
  vmInfo = data.vms.definitions.jenkins;
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
    shares = [
      {
        # Share Nix store for faster builds
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag = "nix-store";
        proto = "virtiofs";
      }
    ];
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

  # Jenkins service
  services.jenkins = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = vmInfo.ports.web;
    withCLI = true;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = builtins.attrValues vmInfo.ports;
  };

  # Packages for CI/CD pipeline
  environment.systemPackages = with pkgs; [
    git
    docker
    kubectl
    curl
    jq
    nix
  ];

  # Enable Docker for container builds
  virtualisation.docker.enable = true;

  system.stateVersion = data.hosts.common.stateVersion;
}
