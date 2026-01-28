# Kubernetes Worker 1 VM (kubeadm 기반)
# VLAN 20 (Services)
#
# 초기화 절차:
# 1. k8s-master에서 kubeadm init 완료 후
# 2. join 토큰 받아서 이 VM에서 kubeadm join 실행
{
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.k8s-worker-1;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
in {
  imports = [
    ../modules/nixos/k8s-kubeadm-base.nix
  ];

  # User configuration
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

  # Worker node firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      vmInfo.ports.ssh # 22
      vmInfo.ports.kubelet # 10250
    ];
    allowedTCPPortRanges = [
      {
        from = vmInfo.ports.nodePortMin;
        to = vmInfo.ports.nodePortMax;
      } # 30000-32767
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
    ];
  };

  # SSH 서비스
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  system.stateVersion = homelabConstants.common.stateVersion;
}

# =============================================================
# kubeadm join 명령어 (k8s-master init 후 수동 실행)
# =============================================================
#
# # k8s-master에서 토큰 확인:
# # kubeadm token create --print-join-command
#
# sudo kubeadm join 10.0.20.10:6443 \
#   --token <token> \
#   --discovery-token-ca-cert-hash sha256:<hash> \
#   --node-name=k8s-worker1
