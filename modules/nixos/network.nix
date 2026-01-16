# Network configuration for homelab server
{homelabConfig, ...}: {
  networking = {
    # 호스트명, 시스템 기본 네트워크 서비스 지정
    hostName = homelabConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
    };

    # 브리지 생성 (vmbr0: WAN용, vmbr1: LAN/VLAN용)
    # vmbr0 : WAN 인터페이스
    # vmbr1 : VLAN 스위치 역할
    # 물리 포트 없이 가상 스위치로만 생성
    bridges = {
      "vmbr0" = {interfaces = ["enp1s0"];};
      "vmbr1" = {interfaces = [];};
    };

    # VLAN 설정 (vmbr1 기반으로 가상 격리)
    vlans = {
      "vlan10" = {
        id = 10;
        interface = "vmbr1";
      };
      "vlan20" = {
        id = 20;
        interface = "vmbr1";
      };
    };

    # IP 주소 할당
    interfaces = {
      # WAN: ISP에서 예약한 정적 IP 설정
      "vmbr0".ipv4.addresses = [
        {
          address = "192.168.45.82";
          prefixLength = 24;
        }
      ];

      # 관리용(VLAN 10) 호스트 IP
      "vlan10".ipv4.addresses = [
        {
          address = "10.0.10.5";
          prefixLength = 24;
        }
      ];

      # 서비스용(VLAN 20) 호스트 IP
      "vlan20".ipv4.addresses = [
        {
          address = "10.0.20.5";
          prefixLength = 24;
        }
      ];
    };

    # 게이트웨이 설정 (ISP 공유기/모뎀 주소)
    defaultGateway = "192.168.45.1";
    nameservers = ["8.8.8.8" "1.1.1.1"];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
}
