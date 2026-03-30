# Kubernetes 노드 공통 설정 (kubeadm 기반)
{
  pkgs,
  lib,
  data,
  microvmTarget,
  ...
}: let
  isVM = microvmTarget != null;
in {
  imports = [
    ../nixos/packages/base.nix
    ../nixos/packages/shell.nix
    ../nixos/packages/editor.nix
    ../nixos/packages/monitoring.nix
    ../nixos/packages/network-tools.nix
    ../nixos/packages/hardware-diag.nix
  ];

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
  # kubelet 서비스
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
  # K8s 클러스터 노드 hosts (3 Master, 2 Worker)
  # ============================================================
  networking.hosts = let
    vms = data.vms.definitions;
  in {
    "${vms.k8s-master-1.ip}" = [vms.k8s-master-1.hostname];
    "${vms.k8s-master-2.ip}" = [vms.k8s-master-2.hostname];
    "${vms.k8s-master-3.ip}" = [vms.k8s-master-3.hostname];
    "${vms.k8s-worker-1.ip}" = [vms.k8s-worker-1.hostname];
    "${vms.k8s-worker-2.ip}" = [vms.k8s-worker-2.hostname];
  };

  # ============================================================
  # 필수 패키지 및 CNI 설정
  # ============================================================
  environment.systemPackages = with pkgs; [
    kubernetes
    kubectx
    k9s
    kubernetes-helm
    cri-tools
    cilium-cli
    etcd
    conntrack-tools
    socat
    iptables
    iproute2
    jq
  ];

  systemd.tmpfiles.rules = [
    "d /etc/kubernetes 0755 root root - -"
    "d /var/lib/kubelet 0755 root root - -"
    "d /opt/cni/bin 0755 root root - -"
    "L+ /opt/cni/bin/loopback - - - - ${pkgs.cni-plugins}/bin/loopback"
    "L+ /opt/cni/bin/portmap - - - - ${pkgs.cni-plugins}/bin/portmap"
  ];

  environment.etc."crictl.yaml".text = ''
    runtime-endpoint: unix:///run/containerd/containerd.sock
    image-endpoint: unix:///run/containerd/containerd.sock
  '';

  networking.firewall = {
    allowedTCPPorts = [10250 4240 4244 4245];
    allowedUDPPorts = [8472];
  };
}
