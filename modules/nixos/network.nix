# homelab 네트워크를 systemd-networkd로 구성
# 브리지/VLAN/TAP 설정을 통합 관리
{homelabConstants, ...}: let
  # 네트워크 상수 참조
  homelabNetwork = homelabConstants.networks;
  # 외부 브리지 인터페이스 이름
  externalIf = "vmbr0";
  # VM/VLAN 상수 묶음
  vms = homelabConstants.vms;
  vlans = homelabConstants.networks.vlans;

  # VLAN ID 축약 별칭
  mgmtVlanId = vlans.management.id;
  svcVlanId = vlans.services.id;
in {
  # 기본 네트워크 설정
  networking = {
    hostName = homelabConstants.host.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    useNetworkd = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };

    # NAT으로 내부 VLAN 라우팅
    nat = {
      enable = true;
      externalInterface = externalIf;
      internalInterfaces = ["vlan10" "vlan20"];
      enableIPv6 = false;
    };
  };

  # 라우팅용 IPv4 포워딩 활성화
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  # systemd-networkd 수동 구성
  systemd.network = {
    # 가상 장치(브리지, VLAN, TAP) 정의
    netdevs = {
      # 메인 브리지 생성 + VLAN 필터링
      "10-vmbr0" = {
        netdevConfig = {
          Name = externalIf;
          Kind = "bridge";
        };
        bridgeConfig.VLANFiltering = true;
      };

      # VLAN 게이트웨이용 내부 인터페이스
      "20-vlan10" = {
        netdevConfig = {
          Name = "vlan10";
          Kind = "vlan";
        };
        vlanConfig.Id = mgmtVlanId;
      };
      "20-vlan20" = {
        netdevConfig = {
          Name = "vlan20";
          Kind = "vlan";
        };
        vlanConfig.Id = svcVlanId;
      };

      # MicroVM TAP 인터페이스 고정 생성
      "30-tap-vault" = {
        netdevConfig = {
          Name = vms.vault.tapId;
          Kind = "tap";
        };
      };
      "30-tap-jenkins" = {
        netdevConfig = {
          Name = vms.jenkins.tapId;
          Kind = "tap";
        };
      };
      "30-tap-registry" = {
        netdevConfig = {
          Name = vms.registry.tapId;
          Kind = "tap";
        };
      };
      "30-tap-k8s-master" = {
        netdevConfig = {
          Name = vms.k8s-master.tapId;
          Kind = "tap";
        };
      };
      "30-tap-k8s-worker1" = {
        netdevConfig = {
          Name = vms.k8s-worker-1.tapId;
          Kind = "tap";
        };
      };
      "30-tap-k8s-worker2" = {
        netdevConfig = {
          Name = vms.k8s-worker-2.tapId;
          Kind = "tap";
        };
      };
    };

    # 인터페이스별 네트워크 설정
    networks = {
      # 물리 NIC를 브리지에 연결
      "05-physical" = {
        matchConfig.Name = "enp1s0";
        networkConfig.Bridge = externalIf;
        linkConfig.RequiredForOnline = "carrier";
      };

      # 브리지에 WAN IP와 VLAN 바인딩
      "10-vmbr0" = {
        matchConfig.Name = externalIf;
        vlan = ["vlan10" "vlan20"];
        address = ["${homelabNetwork.wan.host}/${toString homelabNetwork.wan.prefixLength}"];
        networkConfig = {
          Gateway = homelabNetwork.wan.gateway;
          DNS = homelabNetwork.dns;
          IPv4Forwarding = true;
          IPv6Forwarding = false;
        };
        bridgeVLANs = [
          {VLAN = mgmtVlanId;}
          {VLAN = svcVlanId;}
        ];
        linkConfig.RequiredForOnline = "carrier";
      };

      # VLAN 게이트웨이 IP 할당
      "30-vlan10" = {
        matchConfig.Name = "vlan10";
        address = ["${vlans.management.gateway}/${toString vlans.management.prefixLength}"];
        networkConfig.IPv4Forwarding = true;
      };
      "30-vlan20" = {
        matchConfig.Name = "vlan20";
        address = ["${vlans.services.gateway}/${toString vlans.services.prefixLength}"];
        networkConfig.IPv4Forwarding = true;
      };

      # 각 VM TAP 인터페이스에 VLAN 매핑
      "50-vm-vault" = {
        matchConfig.Name = vms.vault.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            VLAN = mgmtVlanId;
            PVID = mgmtVlanId;
            EgressUntagged = mgmtVlanId;
          }
        ];
      };
      "50-vm-jenkins" = {
        matchConfig.Name = vms.jenkins.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            PVID = mgmtVlanId;
            EgressUntagged = mgmtVlanId;
          }
        ];
      };

      # 서비스 VLAN에 붙는 VM
      "50-vm-registry" = {
        matchConfig.Name = vms.registry.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
      "50-vm-k8s-master" = {
        matchConfig.Name = vms.k8s-master.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
      "50-vm-k8s-worker1" = {
        matchConfig.Name = vms.k8s-worker-1.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
      "50-vm-k8s-worker2" = {
        matchConfig.Name = vms.k8s-worker-2.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
    };
  };
}
