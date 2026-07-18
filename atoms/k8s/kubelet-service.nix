# Atoms: Kubelet Service
# Pure Kubelet systemd service definition.
{
  pkgs,
  lib,
  config,
  ...
}: let
  topology = import ../../network/topology.nix;
  hostName = config.networking.hostName;
  localPathStorage = topology.storage.localPath;
  nodeLabels =
    lib.optionals (builtins.elem hostName localPathStorage.dataNodes)
    (lib.mapAttrsToList (name: value: "${name}=${value}") localPathStorage.nodeSelector);

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

    exec ${pkgs.kubernetes}/bin/kubelet "''${args[@]}" ''${KUBELET_KUBEADM_ARGS:-} ''${KUBELET_TOPOLOGY_ARGS:-} ''${KUBELET_EXTRA_ARGS:-}
  '';

  # Patch kubeadm-generated kubelet config for NodeAuthorizer compatibility.
  #
  # Symptom:
  # - Node authorizer denies LIST/WATCH on ConfigMaps/Secrets with
  #   "no relationship found between node ... and this object".
  # - This can prevent projected serviceaccount volumes (kube-api-access-*)
  #   from being populated with ca.crt/token, causing addons (kube-proxy,
  #   cilium-operator, etc.) to crashloop.
  #
  # Fix:
  # - Force Get-based change detection to avoid LIST/WATCH from kubelet.
  kubeletConfigPatch = pkgs.writeShellScript "kubelet-config-patch" ''
    set -euo pipefail

    p=/var/lib/kubelet/config.yaml
    [[ -f "$p" ]] || exit 0

    if ${pkgs.gnugrep}/bin/grep -q '^configMapAndSecretChangeDetectionStrategy:' "$p"; then
      ${pkgs.gnused}/bin/sed -i \
        's/^configMapAndSecretChangeDetectionStrategy:.*/configMapAndSecretChangeDetectionStrategy: Get/' \
        "$p"
    else
      printf '\nconfigMapAndSecretChangeDetectionStrategy: Get\n' >> "$p"
    fi
  '';
in {
  # NixOS 기본 K8s 서비스 비활성화 (kubeadm 직접 제어를 위해)
  services.kubernetes.roles = lib.mkForce [];
  services.kubernetes.kubelet.enable = lib.mkForce false;

  # kubeadm/join expects these paths to exist even before kubelet starts.
  # (Our kubelet unit may be skipped until kubeadm writes config.yaml.)
  systemd.tmpfiles.rules = [
    "d /var/lib/kubelet 0755 root root - -"
    "d /var/lib/etcd 0700 root root - -"
    "d /etc/kubernetes 0755 root root - -"
    "d /etc/kubernetes/pki 0755 root root - -"
    "d /opt/cni/bin 0755 root root - -"
    "d /var/log/pods 0755 root root - -"
    "d /var/log/containers 0755 root root - -"
  ];

  # ------------------------------------------------------------
  # Kubelet - kubeadm 표준 호환 systemd service
  # kubeadm init/join 완료 전까지 crash loop — 이는 정상 동작
  # ------------------------------------------------------------
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    # kubeadm init/join 전에는 config.yaml이 없으므로 ConditionPathExists가 시작을 차단.
    # init/join 이후에는 부팅 시 자동 시작되어 클러스터가 유지됨.
    wantedBy = lib.mkForce ["multi-user.target"];
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
      # 부팅 시 wantedBy로 pull되지만 condition 미충족 시 조용히 skip됨 (정상 동작).
      ConditionPathExists = "/var/lib/kubelet/config.yaml";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 10;
    };
    path = with pkgs; [
      util-linux
      iproute2
      coreutils
      gnugrep
      gnused
      mount
      bash
      socat
      iptables
      ethtool
      conntrack-tools
    ];

    serviceConfig = {
      ExecStartPre = [
        "-${pkgs.coreutils}/bin/mkdir -p /var/lib/kubelet /opt/cni/bin /etc/kubernetes/pki"
        "${kubeletConfigPatch}"
        "${pkgs.util-linux}/bin/mount --make-rshared /"
      ];
      # kubeadm init/join 전에는 kubeconfig가 없으므로 시작 자체를 스킵 (deploy/switch 시 오버헤드/에러 방지)
      ExecCondition = "${pkgs.bash}/bin/sh -c '[ -f /etc/kubernetes/kubelet.conf ] || [ -f /etc/kubernetes/bootstrap-kubelet.conf ]'";
      # kubeadm이 생성하는 환경변수 파일만 참조 (블로그 방식)
      EnvironmentFile = [
        "-/var/lib/kubelet/kubeadm-flags.env"
        "-/etc/default/kubelet"
      ];
      Environment = lib.optionals (nodeLabels != []) [
        "KUBELET_TOPOLOGY_ARGS=--node-labels=${lib.concatStringsSep "," nodeLabels}"
      ];
      ExecStart = lib.mkForce kubeletWrapper;

      Delegate = "yes";
      KillMode = "process";
      # kubelet은 host mount namespace에서 실행되어야 함.
      # projected volume, CSI 등의 마운트가 containerd에게 보여야 하기 때문.
      # NOTE: ReadWritePaths 등 file system namespace 설정은 암묵적으로
      #       private mount namespace를 생성하므로 사용 금지.
      PrivateTmp = false;
      PrivateMounts = false;
      ProtectSystem = false;

      ProtectControlGroups = false;
      ProtectKernelModules = false;
      ProtectKernelTunables = false;
      RestrictRealtime = false;

      Restart = "always";
      RestartSec = "10s";
    };
  };

  # BPF filesystem은 cni-cilium.nix의 fileSystems."/sys/fs/bpf"에서 선언.
  # kubelet은 sys-fs-bpf.mount를 after/wants로 참조만 함 (위 서비스 설정 참고).
}
