# Kubernetes Worker 1 VM
# VLAN 20 (Services)
# Note: GPU passthrough disabled - AMD iGPU는 호스트에서 ROCm으로 사용
{
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.k8s-worker-1;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
  masterInfo = homelabConstants.vms.k8s-master;
in {
  imports = [
    ../modules/nixos/k8s-base.nix
  ];

  # Kubernetes kubelet configuration with token authentication
  # Token is passed via services.kubernetes.kubelet.kubeconfig
  services.kubernetes.kubelet.kubeconfig.server = "https://${masterInfo.ip}:${toString masterInfo.ports.api}";

  # User configuration
  # Password is managed via sops in mk-microvms.nix (mkVmCommonModule)
  users.mutableUsers = false;

  microvm = {
    hypervisor = homelabConstants.common.hypervisor;
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;

    interfaces = [
      {
        type = "tap";
        id = vmInfo.tapId;
        mac = vmInfo.mac;
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

  # Kubernetes worker configuration
  services.kubernetes = {
    roles = ["node"];
    masterAddress = masterInfo.ip;
    apiserverAddress = "https://${masterInfo.ip}:${toString masterInfo.ports.api}";
    easyCerts = true;
  };

  # Worker node firewall configuration
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

  system.stateVersion = homelabConstants.common.stateVersion;
}
