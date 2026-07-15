{pkgs, ...}: {
  imports = [
    ./common.nix
    ../../atoms/k8s/container-runtime.nix
    ../../atoms/k8s/kubelet-service.nix
    ../../atoms/k8s/cni-cilium.nix
    ../../atoms/k8s/k8s-distro-compat.nix
  ];
  # Master-only operator tools. Common K8s runtime tools live in k8s-distro-compat.nix.
  environment.systemPackages = with pkgs; [
    k9s
    kubeconform
    kustomize
    kyverno
  ];

  # K8s master 포트 (network-base의 [22]에 병합됨)
  networking.firewall.allowedTCPPorts = [6443 2379 2380 10250 10251 10252];
}
