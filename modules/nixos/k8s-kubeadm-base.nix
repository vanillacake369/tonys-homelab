# Kubernetes kubeadm 기반 공통 설정 모듈
# NixOS services.kubernetes 대신 kubeadm으로 클러스터 관리
#
# 이 모듈은 kubelet과 containerd만 설정하고,
# 실제 클러스터 초기화는 kubeadm init/join으로 수행
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
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  # ============================================================
  # 컨테이너 런타임 (containerd)
  # ============================================================
  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri" = {
        sandbox_image = "registry.k8s.io/pause:3.9";
        containerd.runtimes.runc = {
          runtime_type = "io.containerd.runc.v2";
          options.SystemdCgroup = true;
        };
      };
    };
  };

  # ============================================================
  # kubelet 서비스 (systemd 직접 관리)
  # kubeadm이 /var/lib/kubelet/config.yaml 생성
  # ============================================================
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    after = ["containerd.service" "network-online.target"];
    wants = ["containerd.service" "network-online.target"];
    wantedBy = ["multi-user.target"];

    # kubeadm의 환경 파일 로드 (있는 경우)
    serviceConfig = {
      EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";
      # Note: KUBELET_KUBEADM_ARGS는 빈 값일 수 있으므로 쉘에서 처리
      # mount, umount 등 시스템 유틸리티가 PATH에 필요
      ExecStart = pkgs.writeShellScript "kubelet-start" ''
        export PATH=${pkgs.util-linux}/bin:${pkgs.e2fsprogs}/bin:${pkgs.kmod}/bin:$PATH
        exec ${pkgs.kubernetes}/bin/kubelet \
          --config=/var/lib/kubelet/config.yaml \
          --kubeconfig=/etc/kubernetes/kubelet.conf \
          --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
          $KUBELET_KUBEADM_ARGS
      '';
      Restart = "always";
      RestartSec = "10s";
    };

    # kubeadm init/join 전에는 설정 파일이 없으므로 실패할 수 있음
    # ConditionPathExists로 보호
    unitConfig = {
      ConditionPathExists = "/var/lib/kubelet/config.yaml";
    };
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
  # 필수 패키지
  # ============================================================
  environment.systemPackages = with pkgs; [
    kubernetes # kubeadm, kubectl, kubelet
    cri-tools # crictl
    etcd # etcdctl (디버깅용)
    conntrack-tools # CNI 필요
    socat # kubectl port-forward 필요
    iptables
    iproute2
    curl
    jq
  ];

  # ============================================================
  # 필요한 디렉토리 생성
  # /etc/kubernetes, /var/lib/etcd는 mk-microvms.nix에서 virtiofs로 마운트
  # /var/lib/kubelet은 로컬 파일시스템에 생성 (cAdvisor 호환성)
  # ============================================================
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes/manifests 0755 root root - -"
    "d /etc/kubernetes/pki 0755 root root - -"
    "d /var/lib/kubelet 0755 root root - -"
  ];

  # ============================================================
  # crictl 설정 (containerd 사용)
  # ============================================================
  environment.etc."crictl.yaml".text = ''
    runtime-endpoint: unix:///run/containerd/containerd.sock
    image-endpoint: unix:///run/containerd/containerd.sock
    timeout: 10
  '';
}
