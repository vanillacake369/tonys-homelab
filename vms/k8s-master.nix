# Kubernetes Master Node VM
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  ...
}: let
  vmInfo = homelabConstants.vms.k8s-master;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
in {
  # User configuration
  users = {
    mutableUsers = false;
    users.root = {
      # TEMPORARY: 빈 비밀번호 허용 (개발 전용)
      initialHashedPassword = "";
      hashedPassword = "";
      # TODO : 어떻게 하면 이걸 자동으로
      # homelab 에서 가져오도록
      # 할 수 있을까?
      # (아래는 서버 구성 후 직접 가져온것 )
      # TODO : sops 사용하여 암호화하기
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

  # Kubernetes configuration
  services.kubernetes = {
    roles = ["master" "node"];
    masterAddress = vmInfo.hostname;
    apiserverAddress = "https://${vmInfo.ip}:${toString vmInfo.ports.api}";
    flannel.enable = true;
    addons.dns.enable = true;
    easyCerts = true;
    apiserver = {
      enable = true;
      securePort = vmInfo.ports.api;
      advertiseAddress = vmInfo.ip;
    };
    scheduler.enable = true;
    controllerManager.enable = true;
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = builtins.attrValues vmInfo.ports;
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
      PasswordAuthentication = false;
    };
    hostKeys = [
      {
        path = "/var/lib/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # 별도의 etcd 서비스 활성화
  services.etcd = {
    enable = true;
    advertiseClientUrls = ["http://${vmInfo.ip}:2379"];
    listenClientUrls = ["http://0.0.0.0:2379"];
  };

  # Kubernetes tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes
    etcd
    curl
    jq
    bind
  ];

  # Enable container runtime
  virtualisation.containerd.enable = true;

  system.stateVersion = homelabConstants.common.stateVersion;
}
