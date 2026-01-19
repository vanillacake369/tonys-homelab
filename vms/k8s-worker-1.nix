# Kubernetes Worker 1 VM (with GPU passthrough)
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.k8s-worker-1;
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

    # Note: k8s-worker-1 does not use vsock (GPU passthrough configuration)
    # GPU PCI passthrough configuration
    # NOTE: Adjust PCI address after running `lspci` on host
    # Example: lspci | grep VGA
    # qemu.extraArgs = [
    #   "-device" "vfio-pci,host=00:02.0"  # Intel iGPU example
    # ];

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

  # Kubernetes worker configuration
  services.kubernetes = {
    roles = ["node"];
    masterAddress = homelabConstants.vms.k8s-master.hostname;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      vmInfo.ports.ssh
      vmInfo.ports.kubelet
    ];
    allowedTCPPortRanges = [
      {
        from = vmInfo.ports.nodePortMin;
        to = vmInfo.ports.nodePortMax;
      }
    ];
  };

  # SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # TEMPORARY: Allow root with password for development
      PasswordAuthentication = true; # TEMPORARY: Enable password authentication
    };
  };

  # Container runtime and tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes
    curl
    jq
  ];

  # Enable container runtime
  virtualisation.containerd.enable = true;

  system.stateVersion = homelabConstants.common.stateVersion;
}
