# Atoms: K8s Distro Compatibility
# NixOS compatibility layer for standard K8s tools (Symlinks, Packages).
{pkgs, ...}: {
  # FHS symlinks — kubeadm preflight + kubelet runtime이 기대하는 표준 경로
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/socat - - - - ${pkgs.socat}/bin/socat"
    "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /usr/bin/nsenter - - - - ${pkgs.util-linux}/bin/nsenter"
    "L+ /sbin/iptables - - - - ${pkgs.iptables}/bin/iptables"
    "L+ /usr/sbin/conntrack - - - - ${pkgs.conntrack-tools}/bin/conntrack"
    "L+ /var/run/containerd/containerd.sock - - - - /run/containerd/containerd.sock"
  ];

  # crictl endpoint — 기본값 탐색 경고 제거
  environment.etc."crictl.yaml".text = ''
    runtime-endpoint: unix:///run/containerd/containerd.sock
    image-endpoint: unix:///run/containerd/containerd.sock
    timeout: 10
    debug: false
  '';

  # Common K8s Tools
  environment.systemPackages = with pkgs; [
    kubernetes
    cri-tools
    etcd
    kubernetes-helm
    (python3.withPackages (ps: [ps.pyyaml]))
  ];

  # K8s nodes should usually disable the default firewall
  # and use CNI (Cilium) for policy enforcement
  networking.firewall.enable = false;
}
