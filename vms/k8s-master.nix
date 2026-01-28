# Kubernetes Master Node VM
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  vmSecretsPath,
  lib,
  ...
}: let
  # Secrets are shared from host via virtiofs
  clusterJoinToken = "${vmSecretsPath}/k8s/joinToken";
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
      # TODO : 어떻게 하면 이걸 자동으로
      # homelab 에서 가져오도록
      # 할 수 있을까?
      # (아래는 서버 구성 후 직접 가져온것 )
      # TODO : sops 사용하여 암호화하기
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgKsYPtQJYXLQweE0n3bRo1wkNhsNIjbBaA+D1R0/fc limjihoon@homelab"
      ];
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
  # Token is shared from host via virtiofs (read-only)
  services.kubernetes = {
    roles = ["master"];
    masterAddress = vmInfo.ip;
    apiserverAddress = "https://${vmInfo.ip}:${toString vmInfo.ports.api}";
    flannel.enable = true;
    addons.dns.enable = true;
    easyCerts = true;
    apiserver = {
      enable = true;
      securePort = vmInfo.ports.api;
      advertiseAddress = vmInfo.ip;
      tokenAuthFile = clusterJoinToken;
    };
    scheduler.enable = true;
    controllerManager.enable = true;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    # TODO : firewall 이슈로 인해
    # cert 기반 클러스터 조인이 안 되는 현상을
    # 해결하고자 아래와 같이 수동으로 선언
    # allowedTCPPorts = builtins.attrValues vmInfo.ports;
    # 공통 포트
    allowedTCPPorts = [
      8888 # cfssl
      10250 # kubelet API
      10255 # kubelet read-only (선택)
      6443 # API server
      2379 # etcd client
      2380 # etcd peer
      10251 # scheduler (deprecated but some tools use)
      10252 # controller-manager
      10257 # controller-manager secure
      10259 # scheduler secure
    ];

    # NodePort 범위
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];

    # CNI (Flannel VXLAN)
    allowedUDPPorts = [
      8472 # Flannel VXLAN
      8285 # Flannel UDP (백업)
    ];
  };

  # 모든 노드 설정 파일에 공통 추가
  networking.hosts = {
    "${homelabConstants.vms.k8s-master.ip}" = [homelabConstants.vms.k8s-master.hostname];
    "${homelabConstants.vms.k8s-worker-1.ip}" = [homelabConstants.vms.k8s-worker-1.hostname];
    "${homelabConstants.vms.k8s-worker-2.ip}" = [homelabConstants.vms.k8s-worker-2.hostname];
  };

  # NOTE : 테스트를 위한 설정
  # SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # NOTE: etcd는 services.kubernetes.easyCerts = true로 자동 관리됨
  # cert-manager 전환 시 별도 설정 필요

  # Set KUBECONFIG for root user
  environment.variables.KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";

  # Kubernetes tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes
    etcd
    curl
    jq
    bind
  ];

  # ============================================================
  # 1. 커널 모듈 및 sysctl 설정
  # ============================================================
  boot.kernelModules = ["overlay" "br_netfilter"];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = lib.mkForce 1;
    "net.bridge.bridge-nf-call-ip6tables" = lib.mkForce 1;
    "net.ipv4.ip_forward" = lib.mkForce 1;
  };

  # 부팅 시 커널 모듈 확실히 로드
  systemd.services.k8s-kernel-modules = {
    description = "Load Kubernetes required kernel modules";
    before = ["kubelet.service" "containerd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.kmod}/bin/modprobe overlay
      ${pkgs.kmod}/bin/modprobe br_netfilter
      ${pkgs.procps}/bin/sysctl -w net.bridge.bridge-nf-call-iptables=1
      ${pkgs.procps}/bin/sysctl -w net.bridge.bridge-nf-call-ip6tables=1
      ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1
    '';
  };

  # Enable container runtime
  virtualisation.containerd.enable = true;

  system.stateVersion = homelabConstants.common.stateVersion;
}
