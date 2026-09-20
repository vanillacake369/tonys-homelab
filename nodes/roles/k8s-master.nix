{pkgs, ...}: let
  k8sPorts = import ../../atoms/k8s/ports.nix;
in {
  imports = [
    ../profiles/base.nix
    ../../atoms/k8s/container-runtime.nix
    ../../atoms/k8s/kubelet-service.nix
    ../../atoms/k8s/cni-cilium.nix
    ../../atoms/k8s/k8s-distro-compat.nix
  ];
  # Master-only operator tools.
  # Common K8s runtime tools live in k8s-distro-compat.nix.
  environment.systemPackages = with pkgs; [
    k9s
    kubeconform
    kustomize
    kyverno
  ];

  # K8s master control-plane ports; SSH comes from network-base.
  networking.firewall.allowedTCPPorts = k8sPorts.masterTcp;
}
