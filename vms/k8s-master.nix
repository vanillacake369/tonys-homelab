# Kubernetes Master Node VM (kubeadm 기반)
# VLAN 20 (Services)
#
# 초기화 절차:
# 1. VM 배포 후 SSH 접속
# 2. kubeadm init 실행 (아래 명령어 참고)
# 3. CNI (Flannel) 설치
# 4. join 토큰 생성 후 worker 노드에서 join
{
  pkgs,
  data,
  ...
}: let
  vmInfo = data.vms.definitions.k8s-master;
  vlan = data.network.vlans.${vmInfo.vlan};
in {
  imports = [
    ../modules/nixos/k8s-kubeadm-base.nix
  ];

  # User configuration
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

  # Master node firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      vmInfo.ports.ssh # 22
      vmInfo.ports.api # 6443 - API server
      vmInfo.ports.etcdClient # 2379 - etcd client
      vmInfo.ports.etcdPeer # 2380 - etcd peer
      vmInfo.ports.kubelet # 10250 - kubelet API
      vmInfo.ports.scheduler # 10251 - scheduler (deprecated but still used)
      vmInfo.ports.controller # 10252 - controller-manager
      10257 # controller-manager secure
      10259 # scheduler secure
    ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      } # NodePort range
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
    ];
  };

  # KUBECONFIG 환경변수 (kubeadm init 후 사용)
  environment.variables.KUBECONFIG = "/etc/kubernetes/admin.conf";

  # Master 전용 패키지
  environment.systemPackages = with pkgs; [
    etcd
  ];

  # SSH 서비스
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  system.stateVersion = data.hosts.common.stateVersion;
}

# =============================================================
# kubeadm init 명령어 (VM 배포 후 수동 실행)
# =============================================================
#
# sudo kubeadm init \
#   --apiserver-advertise-address=10.0.20.10 \
#   --pod-network-cidr=10.244.0.0/16 \
#   --service-cidr=10.96.0.0/12 \
#   --node-name=k8s-master
#
# mkdir -p $HOME/.kube
# sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
# sudo chown $(id -u):$(id -g) $HOME/.kube/config
#
# # Flannel CNI 설치
# kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
#
# # join 토큰 생성
# kubeadm token create --print-join-command
