# Kubernetes Worker 2 VM
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  vmSecretsPath,
  lib,
  ...
}: let
  # Secrets are shared from host via virtiofs
  clusterJoinToken = "${vmSecretsPath}/k8s/joinToken";
  vmInfo = homelabConstants.vms.k8s-worker-2;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
in {
  # Auto-join service for Kubernetes cluster
  systemd.services.k8s-auto-join = {
    description = "Automatically join the Kubernetes cluster";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    # Skip if already joined (kubelet cert exists)
    unitConfig.ConditionPathExists = "!/var/lib/kubernetes/secrets/kubelet.key";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Extract token from CSV format (first field)
      JOIN_TOKEN=$(cat ${clusterJoinToken} | cut -d',' -f1)

      echo "Starting auto-join with token..."
      echo "$JOIN_TOKEN" | ${pkgs.kubernetes}/bin/nixos-kubernetes-node-join
    '';
  };

  # User configuration
  users = {
    mutableUsers = false;
    users.root = {
      # TEMPORARY: empty password for development
      initialHashedPassword = "";
      hashedPassword = "";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgKsYPtQJYXLQweE0n3bRo1wkNhsNIjbBaA+D1R0/fc limjihoon@homelab"
      ];
    };
  };

  microvm = {
    hypervisor = homelabConstants.common.hypervisor;
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;

    # vsock for systemd-notify support
    vsock.cid = vmInfo.vsockCid;

    interfaces = [
      {
        type = "tap";
        id = vmInfo.tapId;
        mac = vmInfo.mac;
      }
    ];
  };

  # Network configuration
  networking = {
    hostName = vmInfo.hostname;
    useDHCP = false;
    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = vmInfo.ip;
          prefixLength = vlan.prefixLength;
        }
      ];
    };
    defaultGateway = {
      address = vlan.gateway;
      interface = "eth0";
    };
    nameservers = homelabConstants.networks.dns;
  };

  # Kubernetes worker configuration
  services.kubernetes = {
    roles = ["node"];
    masterAddress = homelabConstants.vms.k8s-master.ip;
    apiserverAddress = "https://${homelabConstants.vms.k8s-master.ip}:${toString homelabConstants.vms.k8s-master.ports.api}";
    easyCerts = true;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      vmInfo.ports.ssh
      vmInfo.ports.kubelet
    ];
    allowedTCPPortRanges = [
      {
        from = vmInfo.ports.nodePortMin;
        to = vmInfo.ports.nodePortMax;
      }
    ];
  };

  # 모든 노드 설정 파일에 공통 추가
  networking.hosts = {
    "${homelabConstants.vms.k8s-master.ip}" = [homelabConstants.vms.k8s-master.hostname];
    "${homelabConstants.vms.k8s-worker-1.ip}" = [homelabConstants.vms.k8s-worker-1.hostname];
    "${homelabConstants.vms.k8s-worker-2.ip}" = [homelabConstants.vms.k8s-worker-2.hostname];
  };

  # NOTE : 테스트를 위한 설정
  # SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # Container runtime and tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes
    curl
    jq
    bind
  ];

  # ============================================================
  # 1. 커널 모듈 및 sysctl 설정
  # ============================================================
  boot.kernelModules = ["overlay" "br_netfilter"];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = lib.mkForce 1;
    "net.bridge.bridge-nf-call-ip6tables" = lib.mkForce 1;
    "net.ipv4.ip_forward" = lib.mkForce 1;
  };

  # 부팅 시 커널 모듈 확실히 로드
  systemd.services.k8s-kernel-modules = {
    description = "Load Kubernetes required kernel modules";
    before = ["kubelet.service" "containerd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.kmod}/bin/modprobe overlay
      ${pkgs.kmod}/bin/modprobe br_netfilter
      ${pkgs.procps}/bin/sysctl -w net.bridge.bridge-nf-call-iptables=1
      ${pkgs.procps}/bin/sysctl -w net.bridge.bridge-nf-call-ip6tables=1
      ${pkgs.procps}/bin/sysctl -w net.ipv4.ip_forward=1
    '';
  };

  # Enable container runtime
  virtualisation.containerd.enable = true;

  system.stateVersion = homelabConstants.common.stateVersion;
}
