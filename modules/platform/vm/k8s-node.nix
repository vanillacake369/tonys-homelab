# Josh Rosso Method: Pure Vanilla K8s on NixOS (Resilient Infrastructure)
{ pkgs, lib, data, ... }: {
  imports = [ ../../common/system.nix ];

  # [0] NixOS 내장 K8s 모듈 완전 비활성화
  services.kubernetes.roles = lib.mkForce [];
  services.kubernetes.kubelet.enable = lib.mkForce false;

  my.common = {
    terminal.enable = true;
    monitoring.enable = true;
    network.enable = true;
    editor.enable = true;
    dev.enable = true;
  };

  # [1] Kernel & Network
  boot.kernelModules = ["overlay" "br_netfilter"];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  # [2] Essential Packages (PyYAML, Helm, 필수 도구 포함)
  environment.systemPackages = with pkgs; [
    kubernetes cri-tools etcd conntrack-tools socat iptables
    iproute2 jq ebtables ethtool kmod util-linux mount
    kubernetes-helm
    (python3.withPackages (ps: with ps; [ pyyaml ]))
  ];

  # [3] Container Runtime
  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri" = {
        sandbox_image = "registry.k8s.io/pause:3.10";
        containerd.runtimes.runc = {
          runtime_type = "io.containerd.runc.v2";
          options.SystemdCgroup = true;
        };
      };
    };
  };

  # [4] The Rosso Kubelet (Fully Open & Path-Aware)
  systemd.services.kubelet = {
    description = "Kubernetes Kubelet";
    after = [ "containerd.service" "network-online.target" ];
    wants = [ "containerd.service" "network-online.target" ];
    wantedBy = lib.mkForce [ "multi-user.target" ]; 

    # Kubelet이 필요한 모든 도구를 PATH에 주입
    path = with pkgs; [
      util-linux iproute2 coreutils bash mount socat iptables ethtool procps
    ];

    serviceConfig = {
      ExecStartPre = "-${pkgs.coreutils}/bin/mkdir -p /var/lib/kubelet";
      EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";
      # 쉘 래핑을 제거하고 kubeadm이 관리하도록 단순화 (대신 RestartSec 조정)
      ExecStart = lib.mkForce "${pkgs.kubernetes}/bin/kubelet $KUBELET_KUBEADM_ARGS";
      Restart = "always";
      RestartSec = "10s";
      StartLimitIntervalSec = 0;
      ProtectSystem = "no";
      ProtectControlGroups = "no";
      Delegate = "yes";
      KillMode = "process";
    };
  };

  # [5] Path Mocking (Ubuntu environment simulation)
  systemd.tmpfiles.rules = [
    "d /etc/kubernetes/manifests 0755 root root - -"
    "d /var/lib/kubelet 0755 root root - -"
    "d /var/lib/etcd 0700 root root - -"
    "L+ /opt/cni/bin - - - - ${pkgs.cni-plugins}/bin"
    "L+ /var/run/containerd/containerd.sock - - - - /run/containerd/containerd.sock"
    "L+ /usr/bin/socat - - - - ${pkgs.socat}/bin/socat"
    "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"
    "L+ /usr/bin/umount - - - - ${pkgs.util-linux}/bin/umount"
    "L+ /usr/bin/ip - - - - ${pkgs.iproute2}/bin/ip"
    "L+ /bin/sh - - - - ${pkgs.bash}/bin/sh" # [추가] 일부 스크립트 호환성용
  ];

  networking.firewall.enable = lib.mkForce false;
  networking.hosts = lib.mapAttrs' (name: vm: 
    lib.nameValuePair vm.ip [ vm.hostname name ]
  ) data.vms.definitions;
}
