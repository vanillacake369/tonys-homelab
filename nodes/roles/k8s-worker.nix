# nodes/roles/worker.nix
# K8s Worker Node Strategy
{pkgs, ...}: {
  imports = [
    ./common.nix
    ../../atoms/k8s/container-runtime.nix
    ../../atoms/k8s/kubelet-service.nix
    ../../atoms/k8s/cni-cilium.nix
    ../../atoms/k8s/k8s-distro-compat.nix
  ];

  # K8s worker 포트 (network-base의 [22]에 병합됨)
  networking.firewall.allowedTCPPorts = [10250];
}
