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
  # User configuration
  users = {
    mutableUsers = false;
    users.root = {
      # TEMPORARY: 빈 비밀번호 허용 (개발 전용)
      initialHashedPassword = "";
      hashedPassword = "";
    };
  };
  microvm = {
    hypervisor = homelabConstants.common.hypervisor;
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;

    # vsock for systemd-notify support
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

  # Network configuration
  networking = {
    hostName = vmInfo.hostname;
    useDHCP = false;
    nameservers = homelabConstants.networks.dns;
  };

  # systemd-networkd 설정을 직접 사용하여 유연하게 매칭
  systemd.network.networks."10-lan" = {
    # 모든 이더넷 인터페이스(eth*, enp*)를 대상으로 함
    matchConfig.Type = "ether";

    address = ["${vmInfo.ip}/${toString vlan.prefixLength}"];
    gateway = [vlan.gateway];
    dns = homelabConstants.networks.dns;

    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = false;
    };

    # MicroVM 특성상 링크가 늦게 뜰 수 있으므로 대기 설정 방지
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

  # SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # TEMPORARY: Allow root with password for development
      PasswordAuthentication = true; # TEMPORARY: Enable password authentication
    };
  };

  # Minimal packages
  environment.systemPackages = with pkgs; [
    vault
    curl
    jq
  ];

  system.stateVersion = homelabConstants.common.stateVersion;
}
