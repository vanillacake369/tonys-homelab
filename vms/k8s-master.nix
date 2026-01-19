# Kubernetes Master Node VM
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.k8s-master;
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
  };

  # Network configuration
  networking = {
    hostName = vmInfo.hostname;
    useDHCP = false;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = vmInfo.ip;
          prefixLength = vlan.prefixLength;
        }
      ];
    };
    defaultGateway = {
      address = vlan.gateway;
      interface = "eth0";
    };
    nameservers = homelabConstants.networks.dns;
  };

  # Kubernetes configuration
  services.kubernetes = {
    roles = ["master" "node"];
    masterAddress = vmInfo.hostname;
    apiserverAddress = "https://${vmInfo.ip}:${toString vmInfo.ports.api}";
    easyCerts = true;
    apiserver = {
      securePort = vmInfo.ports.api;
      advertiseAddress = vmInfo.ip;
    };
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

  # Kubernetes tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes
    etcd
    curl
    jq
  ];

  system.stateVersion = homelabConstants.common.stateVersion;
}
