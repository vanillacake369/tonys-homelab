# Network configuration for homelab server
# Pure systemd-networkd configuration with Explicit Declarations
{
  homelabConfig,
  homelabConstants,
  ...
}: let
  homelabNetwork = homelabConstants.networks;
  externalIf = "vmbr0";
  vms = homelabConstants.vms;
  vlans = homelabConstants.networks.vlans;

  # VLAN IDs
  mgmtVlanId = vlans.management.id; # 10
  svcVlanId = vlans.services.id; # 20
in {
  networking = {
    hostName = homelabConfig.hostname;
    networkmanager.enable = false;
    useDHCP = false;
    useNetworkd = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };

    # NAT 설정 (VLAN 게이트웨이 인터페이스를 내부망으로 지정)
    nat = {
      enable = true;
      externalInterface = externalIf;
      internalInterfaces = ["vlan10" "vlan20"];
      enableIPv6 = false;
    };
  };

  # 라우팅 활성화
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  # systemd-networkd 완전 전환 설정
  systemd.network = {
    # -------------------------------------------------------------------------
    # 1. NetDevs: 가상 장치 생성 (Bridge, VLAN, TAP)
    # -------------------------------------------------------------------------
    netdevs = {
      # 브리지 생성 (VLAN Filtering 활성화)
      "10-vmbr0" = {
        netdevConfig = {
          Name = externalIf;
          Kind = "bridge";
        };
        bridgeConfig.VLANFiltering = true;
      };

      # L3 라우팅을 위한 내부 VLAN 인터페이스
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

      # MicroVM용 TAP 인터페이스 명시적 생성
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

    # -------------------------------------------------------------------------
    # 2. Networks: 인터페이스별 네트워크 설정 및 VLAN 바인딩
    # -------------------------------------------------------------------------
    networks = {
      # 물리 인터페이스 (Trunk 포트 연결)
      "05-physical" = {
        matchConfig.Name = "enp1s0";
        networkConfig.Bridge = externalIf;
        linkConfig.RequiredForOnline = "carrier";
      };

      # 메인 브리지 설정 (WAN IP 할당)
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
          {bridgeVLANConfig.VLAN = mgmtVlanId;}
          {bridgeVLANConfig.VLAN = svcVlanId;}
        ];
        linkConfig.RequiredForOnline = "carrier";
      };

      # VLAN 게이트웨이 (L3 인터페이스)
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

      # --- 개별 VM TAP 네트워크 설정 (VLAN 할당) ---

      # VLAN 10 (Management)
      "50-vm-vault" = {
        matchConfig.Name = vms.vault.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            bridgeVLANConfig = {
              VLAN = mgmtVlanId;
              PVID = mgmtVlanId;
              EgressUntagged = mgmtVlanId;
            };
          }
        ];
      };
      "50-vm-jenkins" = {
        matchConfig.Name = vms.jenkins.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            bridgeVLANConfig = {
              PVID = mgmtVlanId;
              EgressUntagged = mgmtVlanId;
            };
          }
        ];
      };

      # VLAN 20 (Services)
      "50-vm-registry" = {
        matchConfig.Name = vms.registry.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            bridgeVLANConfig = {
              PVID = svcVlanId;
              EgressUntagged = svcVlanId;
            };
          }
        ];
      };
      "50-vm-k8s-master" = {
        matchConfig.Name = vms.k8s-master.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            bridgeVLANConfig = {
              PVID = svcVlanId;
              EgressUntagged = svcVlanId;
            };
          }
        ];
      };
      "50-vm-k8s-worker1" = {
        matchConfig.Name = vms.k8s-worker-1.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            bridgeVLANConfig = {
              PVID = svcVlanId;
              EgressUntagged = svcVlanId;
            };
          }
        ];
      };
      "50-vm-k8s-worker2" = {
        matchConfig.Name = vms.k8s-worker-2.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            bridgeVLANConfig = {
              PVID = svcVlanId;
              EgressUntagged = svcVlanId;
            };
          }
        ];
      };
    };
  };
}
