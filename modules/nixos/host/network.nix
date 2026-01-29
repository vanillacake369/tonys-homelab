# homelab 네트워크를 systemd-networkd로 구성
# 브리지/VLAN/TAP 설정을 통합 관리
{
  data,
  lib,
  ...
}: let
  # 네트워크 상수 참조
  homelabNetwork = data.network;
  externalIf = "vmbr0";
  vms = data.vms.definitions;
  vlans = data.network.vlans;

  # VLAN ID 별칭
  mgmtVlanId = vlans.management.id;
  svcVlanId = vlans.services.id;

  # VLAN 이름 → ID 매핑
  vlanIdMap = {
    management = mgmtVlanId;
    services = svcVlanId;
  };

  # VM TAP netdevs 자동 생성
  mkTapNetdevs = lib.mapAttrs' (name: vmInfo:
    lib.nameValuePair "30-tap-${name}" {
      netdevConfig = {
        Name = vmInfo.tapId;
        Kind = "tap";
      };
    }
  ) vms;

  # VM TAP networks 자동 생성
  mkTapNetworks = lib.mapAttrs' (name: vmInfo: let
    vlanId = vlanIdMap.${vmInfo.vlan};
  in
    lib.nameValuePair "50-vm-${name}" {
      matchConfig.Name = vmInfo.tapId;
      networkConfig.Bridge = externalIf;
      bridgeVLANs = [
        {
          PVID = vlanId;
          EgressUntagged = vlanId;
        }
      ];
    }
  ) vms;
in {
  # 기본 네트워크 설정
  networking = {
    hostName = data.hosts.definitions.${data.hosts.default}.hostname;
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

  # systemd-networkd 구성
  systemd.network = {
    # 가상 장치(브리지, VLAN, TAP) 정의
    netdevs =
      {
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
      }
      // mkTapNetdevs;

    # 인터페이스별 네트워크 설정
    networks =
      {
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
      }
      // mkTapNetworks;
  };
}
