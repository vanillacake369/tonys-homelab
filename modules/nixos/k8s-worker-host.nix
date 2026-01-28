# Kubernetes Worker 노드 설정 (호스트용, kubeadm 기반)
# Hybrid K8s Cluster에서 GPU 워크로드 실행을 위한 bare-metal worker
#
# 주의: 호스트는 MicroVM 브릿지(vmbr0)를 사용하므로
# br_netfilter를 활성화하면 VM 통신이 차단될 수 있음
# 따라서 호스트에서는 br_netfilter 없이 K8s를 구성
#
# 초기화 절차:
# 1. k8s-master에서 kubeadm init 완료 후
# 2. join 토큰 받아서 호스트에서 kubeadm join 실행
# 3. kubectl label node homelab gpu=amd node-type=baremetal
{
  pkgs,
  lib,
  homelabConstants,
  ...
}: let
  masterInfo = homelabConstants.vms.k8s-master;
in {
  # ============================================================
  # 커널 모듈 및 sysctl 설정
  # ============================================================
  # overlay: containerd 스토리지 드라이버용
  # br_netfilter: 호스트에서는 로드하지 않음 (MicroVM 브릿지와 충돌)
  boot.kernelModules = ["overlay"];
  boot.kernel.sysctl = {
    # IP 포워딩만 활성화 (K8s pod 네트워크용)
    "net.ipv4.ip_forward" = lib.mkForce 1;
    # bridge-nf-call-iptables는 설정하지 않음 (MicroVM 브릿지 보호)
  };

  # ============================================================
  # K8s 클러스터 노드 hosts 설정
  # ============================================================
  networking.hosts = lib.mkMerge [
    {"${masterInfo.ip}" = [masterInfo.hostname];}
    {"${homelabConstants.vms.k8s-worker-1.ip}" = [homelabConstants.vms.k8s-worker-1.hostname];}
    {"${homelabConstants.vms.k8s-worker-2.ip}" = [homelabConstants.vms.k8s-worker-2.hostname];}
  ];

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

    # kubeadm join 전에는 설정 파일이 없으므로 실패할 수 있음
    unitConfig = {
      ConditionPathExists = "/var/lib/kubelet/config.yaml";
    };
  };

  # ============================================================
  # K8s 관련 패키지
  # ============================================================
  environment.systemPackages = with pkgs; [
    kubernetes # kubeadm, kubectl, kubelet
    cri-tools # crictl
    conntrack-tools # CNI 필요
    socat # kubectl port-forward 필요
    iptables
    iproute2
    curl
    jq
    bind # nslookup
  ];

  # ============================================================
  # 필요한 디렉토리 생성
  # ============================================================
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes 0755 root root - -"
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

  # ============================================================
  # 방화벽 설정
  # ============================================================
  networking.firewall = {
    allowedTCPPorts = [
      10250 # kubelet API
      10255 # kubelet read-only (metrics)
    ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      } # NodePort 범위
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
      8285 # Flannel UDP (fallback)
    ];
  };
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
#   --node-name=homelab
#
# # GPU 노드 레이블 추가 (k8s-master에서 실행)
# kubectl label node homelab gpu=amd node-type=baremetal
