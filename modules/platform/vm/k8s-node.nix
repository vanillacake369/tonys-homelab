# Josh Rosso Method: Vanilla Kubernetes Infrastructure
# REFER TO https://joshrosso.com/c/nix-k8s/
{
  pkgs,
  lib,
  data,
  ...
}: {
  # ------------------------------------------------------------
  # NixOS Native K8s Shield (Disable conflicting services)
  # ------------------------------------------------------------
  services.kubernetes.roles = lib.mkForce [];
  services.kubernetes.kubelet.enable = lib.mkForce false;

  # Enable core system tools via the unified options
  my.common = {
    terminal.enable = true;
    monitoring.enable = true;
    network.enable = true;
    editor.enable = true;
    dev.enable = true;
  };

  # ------------------------------------------------------------
  # Kernel & Network Plumbing (Cilium/K8s optimized)
  # ------------------------------------------------------------
  boot.kernelModules = [
    "overlay"
    "br_netfilter"
    "ip_tables"
    "nf_conntrack"
    "xt_bpf"
    "xt_mark"
    "xt_tcpudp"
    "xt_addrtype"
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "vm.overcommit_memory" = 1;
  };

  fileSystems."/sys/fs/bpf" = {
    device = "bpffs";
    fsType = "bpf";
  };

  # ------------------------------------------------------------
  # K8s Essential Binaries
  # ------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    kubernetes
    cri-tools
    etcd
    conntrack-tools
    socat
    iptables
    iproute2
    jq
    ebtables
    ethtool
    kmod
    util-linux
    mount
    kubernetes-helm
    (python3.withPackages (ps: with ps; [pyyaml]))
  ];

  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri" = {
        sandbox_image = "registry.k8s.io/pause:3.10";
        containerd.runtimes.runc = {
          runtime_type = "io.containerd.runc.v2";
          options.SystemdCgroup = true;
        };
      };
    };
  };

  # ------------------------------------------------------------
  # Kubelet (Fully Open & Path-Aware)
  # ------------------------------------------------------------
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    after = ["containerd.service" "network-online.target"];
    wants = ["containerd.service" "network-online.target"];

    path = with pkgs; [
      util-linux
      iproute2
      coreutils
      bash
      mount
      socat
      iptables
      ethtool
      procps
    ];

    serviceConfig = {
      ExecStartPre = "-${pkgs.coreutils}/bin/mkdir -p /var/lib/kubelet";
      EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";
      ExecStart = lib.mkForce "${pkgs.kubernetes}/bin/kubelet --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml $KUBELET_KUBEADM_ARGS";
      Restart = "always";
      RestartSec = "10s";
      StartLimitIntervalSec = 0;
      ProtectSystem = "no";
      ProtectControlGroups = "no";
      Delegate = "yes";
      KillMode = "process";
    };
  };

  # ------------------------------------------------------------
  # OS Mocking (The 'Ubuntu Simulation')
  # ------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes/manifests 0755 root root - -"
    "d /var/lib/kubelet 0755 root root - -"
    "d /var/lib/etcd 0700 root root - -"
    "d /etc/cni/net.d 0755 root root - -"
    "L+ /opt/cni/bin - - - - ${pkgs.cni-plugins}/bin"
    "L+ /usr/bin/socat - - - - ${pkgs.socat}/bin/socat"
    "L+ /usr/bin/ip - - - - ${pkgs.iproute2}/bin/ip"
    "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /usr/bin/umount - - - - ${pkgs.util-linux}/bin/umount"
    "L+ /usr/bin/iptables - - - - ${pkgs.iptables}/bin/iptables"
    "L+ /usr/bin/ebtables - - - - ${pkgs.ebtables}/bin/ebtables"
    "L+ /usr/bin/ethtool - - - - ${pkgs.ethtool}/bin/ethtool"
    "L+ /var/run/containerd/containerd.sock - - - - /run/containerd/containerd.sock"
  ];

  networking.firewall.enable = lib.mkForce false;
}
