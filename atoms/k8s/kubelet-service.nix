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
  # NOTE:
  # args 문자열(KUBELET_KUBEADM_ARGS/KUBELET_EXTRA_ARGS)은
  # 공백 split이 필요하므로 unquoted expansion 사용
  # (kubeadm-flags.env가 제공하는 형식과 동일)
  kubeletWrapper = pkgs.writeShellScript "kubelet-start" ''
    set -euo pipefail

    # kubeadm 흐름에서는 kubelet이 bootstrap kubeconfig로 인증서를 발급받고,
    # 최종 kubeconfig 경로(/etc/kubernetes/kubelet.conf)에 클라이언트를 생성함.
    # 따라서 kubelet.conf 파일이 아직 없더라도 --kubeconfig 경로는 항상 넘겨야 함.
    args=(
      --config=/var/lib/kubelet/config.yaml
      --kubeconfig=/etc/kubernetes/kubelet.conf
    )

    if [[ -f /etc/kubernetes/bootstrap-kubelet.conf ]]; then
      args+=(--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf)
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
    # kubelet은 kubeadm이 필요한 타이밍에 start/restart 하도록 두는 편이 안전함.
    # (NixOS/Colmena activation 시점에 자동 시작되면 unit 실패가 곧 배포 실패로 이어질 수 있음)
    wantedBy = lib.mkForce [];
    after = [
      "network-online.target"
      "containerd.service"
      "sys-fs-bpf.mount"
    ];
    wants = [
      "network-online.target"
      "containerd.service"
      "sys-fs-bpf.mount"
    ];
    restartIfChanged = false;
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
      ExecCondition = "${pkgs.bash}/bin/sh -c '[ -f /etc/kubernetes/kubelet.conf ] || [ -f /etc/kubernetes/bootstrap-kubelet.conf ]'";
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

  # Explicitly mount BPF filesystem for Cilium
  # Cilium 공식 sys-fs-bpf.mount 와 동일한 dependency 그래프
  systemd.mounts = [
    {
      what = "bpffs";
      where = "/sys/fs/bpf";
      type = "bpf";
      options = "rw,nosuid,nodev,noexec,relatime,mode=700";

      unitConfig = {
        DefaultDependencies = "no";
        Description = "Cilium BPF mounts";
        Documentation = "https://docs.cilium.io/";
      };
      before = ["local-fs.target" "umount.target"];
      after = ["swap.target"];

      wantedBy = ["multi-user.target"];
    }
  ];
}
