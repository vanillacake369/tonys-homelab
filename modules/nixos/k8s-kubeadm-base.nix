# Kubernetes kubeadm 기반 공통 설정 모듈
# NixOS services.kubernetes 대신 kubeadm으로 클러스터 관리
#
# 이 모듈은 kubelet과 containerd만 설정하고,
# 실제 클러스터 초기화는 kubeadm init/join으로 수행
{
  pkgs,
  lib,
  data,
  ...
}: {
  # ============================================================
  # 커널 모듈 및 sysctl 설정
  # MicroVM은 호스트 커널을 공유하므로 boot.kernelModules가 동작하지 않을 수 있음
  # systemd oneshot 서비스로 런타임에 모듈 로드 및 sysctl 적용
  # ============================================================
  boot.kernelModules = ["overlay" "br_netfilter"];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  # MicroVM 환경에서 커널 모듈이 부팅 시 로드되지 않는 경우 대비
  systemd.services.k8s-kernel-modules = {
    description = "Load kernel modules for Kubernetes";
    before = ["kubelet.service" "containerd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "k8s-load-modules" ''
        ${pkgs.kmod}/bin/modprobe overlay
        ${pkgs.kmod}/bin/modprobe br_netfilter
        # sysctl 적용 (br_netfilter 로드 후에야 경로가 존재)
        echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
        echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
        echo 1 > /proc/sys/net/ipv4/ip_forward
      '';
    };
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
    after = ["containerd.service" "network-online.target" "k8s-kernel-modules.service"];
    wants = ["containerd.service" "network-online.target" "k8s-kernel-modules.service"];
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
    {"${data.vms.definitions.k8s-master.ip}" = [data.vms.definitions.k8s-master.hostname];}
    {"${data.vms.definitions.k8s-worker-1.ip}" = [data.vms.definitions.k8s-worker-1.hostname];}
    {"${data.vms.definitions.k8s-worker-2.ip}" = [data.vms.definitions.k8s-worker-2.hostname];}
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
  #
  # /etc/kubernetes, /var/lib/etcd: virtiofs로 호스트에서 마운트 (영속)
  # /var/lib/kubelet: qcow2 블록 디바이스로 마운트 (영속, cAdvisor 호환)
  # ============================================================
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes/manifests 0755 root root - -"
    "d /etc/kubernetes/pki 0755 root root - -"
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
