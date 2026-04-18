{pkgs, ...}: {
  imports = [
    ./common.nix
    ../../atoms/k8s/container-runtime.nix
    ../../atoms/k8s/kubelet-service.nix
    ../../atoms/k8s/cni-cilium.nix
    ../../atoms/k8s/k8s-distro-compat.nix
  ];

  environment.systemPackages = with pkgs; [
    kubernetes
    cri-tools
    etcd
    kubernetes-helm
  ];

  # K8s master 포트 (network-base의 [22]에 병합됨)
  networking.firewall.allowedTCPPorts = [6443 2379 2380 10250 10251 10252];

  # OS Mocking for kubeadm
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/socat - - - - ${pkgs.socat}/bin/socat"
    "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /var/run/containerd/containerd.sock - - - - /run/containerd/containerd.sock"
  ];
}
