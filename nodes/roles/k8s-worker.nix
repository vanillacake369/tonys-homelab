# K8s Worker Node Strategy
_: let
  k8sPorts = import ../../atoms/k8s/ports.nix;
in {
  imports = [
    ../profiles/base.nix
    ../../atoms/k8s/container-runtime.nix
    ../../atoms/k8s/kubelet-service.nix
    ../../atoms/k8s/cni-cilium.nix
    ../../atoms/k8s/k8s-distro-compat.nix
  ];

  # K8s worker kubelet port; SSH comes from network-base.
  networking.firewall.allowedTCPPorts = k8sPorts.workerTcp;
}
