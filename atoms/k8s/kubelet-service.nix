# Atoms: Kubelet Service
# Pure Kubelet systemd service definition.
{
  pkgs,
  lib,
  ...
}: let
  # kubelet ExecStart wrapper:
  # - kubeadm이 생성하는 kubeconfig/flags 파일이 있을 때만 올바른 모드로 실행
  # - kubeconfig가 없으면 standalone 모드로 뜨며 webhook auth에서 실패하므로 방지
  #
  # NOTE: args 문자열(KUBELET_KUBEADM_ARGS/KUBELET_EXTRA_ARGS)은 공백 split이 필요하므로 unquoted expansion 사용
  # (kubeadm-flags.env가 제공하는 형식과 동일)
  kubeletWrapper = pkgs.writeShellScript "kubelet-start" ''
    set -euo pipefail

    args=(--config=/var/lib/kubelet/config.yaml)

    if [[ -f /etc/kubernetes/bootstrap-kubelet.conf ]]; then
      args+=(--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf)
    fi

    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
      args+=(--kubeconfig=/etc/kubernetes/kubelet.conf)
    fi

    exec ${pkgs.kubernetes}/bin/kubelet "''${args[@]}" ''${KUBELET_KUBEADM_ARGS:-} ''${KUBELET_EXTRA_ARGS:-}
  '';
in {
  # NixOS 기본 K8s 서비스 비활성화 (kubeadm 직접 제어를 위해)
  services.kubernetes.roles = lib.mkForce [];
  services.kubernetes.kubelet.enable = lib.mkForce false;

  # ------------------------------------------------------------
  # Kubelet - kubeadm 표준 호환 systemd service
  # kubeadm init/join 완료 전까지 crash loop — 이는 정상 동작
  # ------------------------------------------------------------
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    wantedBy = ["network-online.target"];
    after = ["network-online.target" "containerd.service"];
    wants = ["network-online.target" "containerd.service"];
    unitConfig = {
      # kubeadm init/join 전에는 설정 파일이 없으므로 kubelet을 아예 시작하지 않음.
      # (cleanup/reset 이후에도 동일하게 조용히 대기)
      ConditionPathExists = "/var/lib/kubelet/config.yaml";
      StartLimitIntervalSec = 0;
    };
    path = with pkgs; [
      util-linux
      iproute2
      coreutils
      mount
      bash
      socat
      iptables
      ethtool
      conntrack-tools
    ];

    serviceConfig = {
      ExecStartPre = "-${pkgs.coreutils}/bin/mkdir -p /var/lib/kubelet /opt/cni/bin /etc/kubernetes/pki";
      # kubeadm init/join 전에는 kubeconfig가 없으므로 시작 자체를 스킵 (deploy/switch 시 오버헤드/에러 방지)
      ExecCondition = "${pkgs.coreutils}/bin/test" + " -f /etc/kubernetes/kubelet.conf -o -f /etc/kubernetes/bootstrap-kubelet.conf";
      # kubeadm이 생성하는 환경변수 파일만 참조 (블로그 방식)
      EnvironmentFile = [
        "-/var/lib/kubelet/kubeadm-flags.env"
        "-/etc/default/kubelet"
      ];
      ExecStart = lib.mkForce kubeletWrapper;

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
