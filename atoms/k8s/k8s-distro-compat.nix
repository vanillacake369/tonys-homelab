# Atoms: K8s Distro Compatibility
# NixOS compatibility layer for standard K8s tools (Symlinks, Packages).
{pkgs, ...}: {
  # OS Mocking for kubeadm & standard K8s tools
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/socat - - - - ${pkgs.socat}/bin/socat"
    "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /var/run/containerd/containerd.sock - - - - /run/containerd/containerd.sock"
  ];

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
