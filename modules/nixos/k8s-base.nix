# Kubernetes 공통 설정 모듈
# K8s master/worker 노드에서 공유되는 설정
{
  pkgs,
  lib,
  homelabConstants,
  ...
}: {
  # ============================================================
  # 커널 모듈 및 sysctl 설정
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

  # ============================================================
  # K8s 클러스터 노드 hosts 설정
  # ============================================================
  networking.hosts = lib.mkMerge [
    {"${homelabConstants.vms.k8s-master.ip}" = [homelabConstants.vms.k8s-master.hostname];}
    {"${homelabConstants.vms.k8s-worker-1.ip}" = [homelabConstants.vms.k8s-worker-1.hostname];}
    {"${homelabConstants.vms.k8s-worker-2.ip}" = [homelabConstants.vms.k8s-worker-2.hostname];}
  ];

  # ============================================================
  # 공통 방화벽 설정 (CNI - Flannel)
  # ============================================================
  networking.firewall.allowedUDPPorts = [
    8472 # Flannel VXLAN
    8285 # Flannel UDP (백업)
  ];

  # ============================================================
  # 컨테이너 런타임 및 공통 패키지
  # ============================================================
  virtualisation.containerd.enable = true;

  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes
    curl
    jq
    bind
  ];

  # ============================================================
  # SSH 서비스 (hardened)
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
}
