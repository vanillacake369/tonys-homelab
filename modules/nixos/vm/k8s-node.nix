# Kubernetes 노드 공통 설정 (kubeadm 기반)
# VM과 호스트 모두 이 모듈을 import
#
# isVM:
#   true  — VM용 (br_netfilter 활성화, oneshot 커널 모듈 로더)
#   false — 호스트용 (br_netfilter 비활성화, MicroVM 브릿지 보호)
#
# Note: Cilium은 eBPF 기반이라 br_netfilter 불필요
#       호스트에서 br_netfilter 활성화 시 VM 브릿지 트래픽이 iptables를 거쳐 차단됨
{
  pkgs,
  lib,
  data,
  microvmTarget,
  ...
}: let
  # VM: microvmTarget이 specialArgs로 전달됨
  # 호스트: microvmTarget 없음
  isVM = microvmTarget != null;
in {
  imports = [
    ../packages/base.nix
    ../packages/shell.nix
    ../packages/editor.nix
    ../packages/monitoring.nix
    ../packages/network-tools.nix
    ../packages/hardware-diag.nix
  ];

  # ============================================================
  # 커널 모듈 및 sysctl
  # ============================================================
  # br_netfilter: VM에서만 활성화 (Cilium은 eBPF 사용, 호스트에서 불필요)
  # 호스트에서 활성화 시 MicroVM 브릿지 트래픽이 iptables에 의해 차단됨
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
        cni = {
          # /opt/cni/bin: Cilium이 cilium-cni를 설치하는 경로
          # NixOS cni-plugins는 systemd.tmpfiles로 심볼릭 링크
          bin_dir = "/opt/cni/bin";
          conf_dir = "/etc/cni/net.d";
        };
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
      ExecStart = let
        # 호스트: swap 허용 (--fail-swap-on=false)
        # VM: swap 없음 (기본값)
        swapFlag = lib.optionalString (!isVM) "--fail-swap-on=false";
      in
        pkgs.writeShellScript "kubelet-start" ''
          export PATH=${pkgs.util-linux}/bin:${pkgs.e2fsprogs}/bin:${pkgs.kmod}/bin:$PATH
          exec ${pkgs.kubernetes}/bin/kubelet \
            --config=/var/lib/kubelet/config.yaml \
            --kubeconfig=/etc/kubernetes/kubelet.conf \
            --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
            ${swapFlag} \
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
  # 필수 패키지 (K8s 전용)
  # ============================================================
  environment.systemPackages = with pkgs; [
    kubernetes # kubeadm, kubectl, kubelet
    kubectx
    k9s
    kubernetes-helm
    kubectl-tree
    cri-tools # crictl
    # cni-plugins: /opt/cni/bin에 심볼릭 링크로 제공 (tmpfiles.rules)
    # systemPackages에 추가하면 iproute2의 bridge 명령과 충돌
    cilium-cli # Cilium CNI management
    etcd # etcdctl
    conntrack-tools # CNI
    socat # kubectl port-forward
    iptables
    iproute2
    jq
    bpftools
  ];

  # ============================================================
  # 필요한 디렉토리 및 CNI 플러그인
  # ============================================================
  # CNI 표준 경로: /opt/cni/bin (containerd, Cilium 모두 이 경로 사용)
  # Cilium은 cilium-cni만 설치하므로 loopback, portmap 등은 별도 제공 필요
  # ref: https://docs.cilium.io/en/stable/installation/cni-chaining-portmap
  # NixOS: immutable store이므로 심볼릭 링크로 제공
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes 0755 root root - -"
    "d /etc/kubernetes/manifests 0755 root root - -"
    "d /etc/kubernetes/pki 0755 root root - -"
    "d /var/lib/kubelet 0755 root root - -"
    "d /etc/cni 0755 root root - -"
    "d /etc/cni/net.d 0755 root root - -"
    # CNI plugins at standard path /opt/cni/bin
    "d /opt/cni/bin 0755 root root - -"
    "L+ /opt/cni/bin/loopback - - - - ${pkgs.cni-plugins}/bin/loopback"
    "L+ /opt/cni/bin/bridge - - - - ${pkgs.cni-plugins}/bin/bridge"
    "L+ /opt/cni/bin/host-local - - - - ${pkgs.cni-plugins}/bin/host-local"
    "L+ /opt/cni/bin/portmap - - - - ${pkgs.cni-plugins}/bin/portmap"
    "L+ /opt/cni/bin/bandwidth - - - - ${pkgs.cni-plugins}/bin/bandwidth"
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
      4240 # Cilium health check
      4244 # Hubble server
      4245 # Hubble relay
    ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      } # NodePort
    ];
    allowedUDPPorts = [
      8472 # VXLAN (Cilium/Flannel)
    ];
  };
}
