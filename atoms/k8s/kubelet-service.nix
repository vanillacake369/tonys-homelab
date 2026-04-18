# Atoms: Kubelet Service
# Pure Kubelet systemd service definition.
{
  pkgs,
  lib,
  ...
}: {
  # NixOS 기본 K8s 서비스 비활성화 (kubeadm 직접 제어를 위해)
  services.kubernetes.roles = lib.mkForce [];
  services.kubernetes.kubelet.enable = lib.mkForce false;

  # ------------------------------------------------------------
  # Kubelet - The "Naked" Configuration
  # ------------------------------------------------------------
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    after = ["containerd.service"];
    wants = ["containerd.service"];
    unitConfig.StartLimitIntervalSec = 0;
    path = with pkgs; [
      util-linux
      iproute2
      coreutils
      mount
      bash
      socat
      iptables
      ethtool
    ];

    serviceConfig = {
      ExecStartPre = "-${pkgs.coreutils}/bin/mkdir -p /var/lib/kubelet /opt/cni/bin /etc/kubernetes/pki";
      EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";
      ExecStart = lib.mkForce "${pkgs.kubernetes}/bin/kubelet --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml $KUBELET_KUBEADM_ARGS";

      Delegate = "yes";
      KillMode = "process";
      MountFlags = "shared";
      PrivateTmp = false;
      ProtectSystem = false;
      ReadWritePaths = ["/"];

      Restart = "always";
      RestartSec = "10s";
    };
  };
}
