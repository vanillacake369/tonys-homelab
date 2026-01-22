# Network configuration for homelab server
# Pure systemd-networkd configuration with Explicit Declarations
{
  homelabConfig,
  homelabConstants,
  ...
}: let
  homelabNetwork = homelabConstants.networks;
  externalIf = "vmbr0";
  internalBridge = "vmbr1";
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

  };

  # systemd-networkd 완전 전환 설정
  environment.etc."qemu/bridge.conf".text = ''
allow ${externalIf}
allow ${internalBridge}
allow all
  '';

  systemd.network = {
    wait-online = {
      anyInterface = true;
      extraArgs = [
        "--ignore=vmbr1"
      ];
    };

    # -------------------------------------------------------------------------
    # 1. NetDevs: 가상 장치 생성 (Bridge, VLAN, TAP)
    # -------------------------------------------------------------------------
    netdevs = {
      # 브리지 생성 (WAN, LAN Trunk)
      "10-vmbr0" = {
        netdevConfig = {
          Name = externalIf;
          Kind = "bridge";
        };
        bridgeConfig.VLANFiltering = true;
      };
      "10-vmbr1" = {
        netdevConfig = {
          Name = internalBridge;
          Kind = "bridge";
        };
        bridgeConfig.VLANFiltering = true;
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
      # 물리 인터페이스 (WAN 연결)
      "05-physical" = {
        matchConfig.Name = "enp1s0";
        networkConfig.Bridge = externalIf;
        linkConfig.RequiredForOnline = "carrier";
      };

      # WAN 브리지 (호스트 관리용 IP만 할당)
      "10-vmbr0" = {
        matchConfig.Name = externalIf;
        address = ["${homelabNetwork.wan.host}/${toString homelabNetwork.wan.prefixLength}"];
        networkConfig = {
          Gateway = homelabNetwork.wan.gateway;
          DNS = homelabNetwork.dns;
        };
        linkConfig.RequiredForOnline = "carrier";
      };

      # LAN 트렁크 브리지 (OPNsense가 라우팅 담당)
      "10-vmbr1" = {
        matchConfig.Name = internalBridge;
        bridgeVLANs = [
          {VLAN = mgmtVlanId;}
          {VLAN = svcVlanId;}
        ];
        networkConfig.ConfigureWithoutCarrier = true;
        linkConfig.RequiredForOnline = "carrier";
      };

      # OPNsense WAN/LAN TAP

      # --- 개별 VM TAP 네트워크 설정 (VLAN 할당) ---

      # VLAN 10 (Management)
      "50-vm-vault" = {
        matchConfig.Name = vms.vault.tapId;
        networkConfig.Bridge = internalBridge;
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
        networkConfig.Bridge = internalBridge;
        bridgeVLANs = [
          {
            PVID = mgmtVlanId;
            EgressUntagged = mgmtVlanId;
          }
        ];
      };

      # VLAN 20 (Services)
      "50-vm-registry" = {
        matchConfig.Name = vms.registry.tapId;
        networkConfig.Bridge = internalBridge;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
      "50-vm-k8s-master" = {
        matchConfig.Name = vms.k8s-master.tapId;
        networkConfig.Bridge = internalBridge;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
      "50-vm-k8s-worker1" = {
        matchConfig.Name = vms.k8s-worker-1.tapId;
        networkConfig.Bridge = internalBridge;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
      "50-vm-k8s-worker2" = {
        matchConfig.Name = vms.k8s-worker-2.tapId;
        networkConfig.Bridge = internalBridge;
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
