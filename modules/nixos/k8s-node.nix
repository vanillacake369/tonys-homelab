# Kubernetes 노드 공통 설정 (kubeadm 기반)
# VM과 호스트 모두 이 모듈을 import
#
# isVM:
#   true  — VM용 (br_netfilter + oneshot 커널 모듈 로더)
#   false — 호스트용 (br_netfilter 제외, VM 브릿지 충돌 방지)
{
  pkgs,
  lib,
  data,
  microvmTarget,
  ...
}: let
  # VM: microvmTarget이 specialArgs로 전달됨 → br_netfilter 활성화
  # 호스트: microvmTarget 없음 → br_netfilter 비활성화 (VM 브릿지 충돌 방지)
  isVM = microvmTarget != null;
in {
  # ============================================================
  # 커널 모듈 및 sysctl
  # ============================================================
  boot.kernelModules =
    ["overlay"]
    ++ lib.optionals isVM ["br_netfilter"];

  boot.kernel.sysctl =
    {
      "net.ipv4.ip_forward" = lib.mkForce 1;
    }
    // lib.optionalAttrs isVM {
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

  # MicroVM: 커널 모듈이 부팅 시 로드되지 않는 경우 대비
  systemd.services.k8s-kernel-modules = lib.mkIf isVM {
    description = "Load kernel modules for Kubernetes";
    before = ["kubelet.service" "containerd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "k8s-load-modules" ''
        ${pkgs.kmod}/bin/modprobe overlay
        ${pkgs.kmod}/bin/modprobe br_netfilter
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
  # ============================================================
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    after =
      ["containerd.service" "network-online.target"]
      ++ lib.optionals isVM ["k8s-kernel-modules.service"];
    wants =
      ["containerd.service" "network-online.target"]
      ++ lib.optionals isVM ["k8s-kernel-modules.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";
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

    unitConfig = {
      ConditionPathExists = "/var/lib/kubelet/config.yaml";
    };
  };

  # ============================================================
  # K8s 클러스터 노드 hosts
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
    etcd # etcdctl
    conntrack-tools # CNI
    socat # kubectl port-forward
    iptables
    iproute2
    curl
    jq
    bind # nslookup
  ];

  # ============================================================
  # 필요한 디렉토리
  # ============================================================
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes 0755 root root - -"
    "d /etc/kubernetes/manifests 0755 root root - -"
    "d /etc/kubernetes/pki 0755 root root - -"
    "d /var/lib/kubelet 0755 root root - -"
  ];

  # ============================================================
  # crictl 설정
  # ============================================================
  environment.etc."crictl.yaml".text = ''
    runtime-endpoint: unix:///run/containerd/containerd.sock
    image-endpoint: unix:///run/containerd/containerd.sock
    timeout: 10
  '';

  # ============================================================
  # 방화벽 (호스트 + VM 공통)
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
      } # NodePort
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
      8285 # Flannel UDP (fallback)
    ];
  };
}
