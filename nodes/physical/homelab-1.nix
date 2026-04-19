# Node: homelab-1 (Physical Host)
{
  config,
  lib,
  pkgs,
  ...
}: let
  # 네트워크 상수 참조 (topology.nix: 공유 VLAN/WAN 상수)
  network = import ../../network/topology.nix;
  externalIf = "vmbr0";
  vlans = network.vlans;

  # VLAN ID 별칭
  mgmtVlanId = vlans.management.id;
  svcVlanId = vlans.services.id;

  # VM TAP 장치 정의: topology.nix vms 에서 자동 도출 (VM 추가/제거 시 수정 불필요)
  # NOTE: Phase 4에서 libvirt VM Domain으로 TAP 생성 이관 예정
  #       현재는 systemd-networkd가 직접 생성
  vmTapDefs = builtins.attrValues (
    builtins.mapAttrs (name: vm: {
      inherit name;
      tapId = vm.tapId;
    })
    network.vms
  );

  # VM TAP netdevs 생성 (모든 VM은 services VLAN)
  mkTapNetdevs = builtins.listToAttrs (map (vm: {
      name = "30-tap-${vm.name}";
      value = {
        netdevConfig = {
          Name = vm.tapId;
          Kind = "tap";
        };
      };
    })
    vmTapDefs);

  # VM TAP → bridge VLAN 할당 (services VLAN 20)
  mkTapNetworks = builtins.listToAttrs (map (vm: {
      name = "50-vm-${vm.name}";
      value = {
        matchConfig.Name = vm.tapId;
        networkConfig.Bridge = externalIf;
        bridgeVLANs = [
          {
            PVID = svcVlanId;
            EgressUntagged = svcVlanId;
          }
        ];
      };
    })
    vmTapDefs);

  clientSecret = config.sops.secrets."tailscale/clientSecret".path;
in {
  imports = [
    ../interface.nix
    ../roles/common.nix
    ../../atoms/user/limjihoon.nix
    ../../atoms/system/git.nix
    ../../atoms/network/ssh-client.nix
    ./disko-config.nix
  ];

  node = {
    ip = network.wan.host;
    role = "host";
    hostType = "physical";
    user = "limjihoon";
  };

  # EFI 부트로더 (disko-config.nix 의 ESP 파티션 사용)
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  system.stateVersion = "24.11";

  # ===========================================================================
  # sops-nix
  # ===========================================================================
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  };

  # ===========================================================================
  # Tailscale (Exit Node & Autoconnect)
  # ===========================================================================
  sops.secrets."tailscale/clientSecret" = {};

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  environment.systemPackages = [pkgs.tailscale];

  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--ssh"
      "--netfilter-mode=nodivert"
      "--advertise-exit-node"
    ];
  };

  # ===========================================================================
  # 네트워크
  # ===========================================================================
  networking = {
    # NAT으로 내부 VLAN → WAN 라우팅
    nat = {
      enable = true;
      externalInterface = externalIf;
      internalInterfaces = ["vlan10" "vlan20"];
      enableIPv6 = false;
    };

    firewall = {
      allowedUDPPorts = [config.services.tailscale.port];
      trustedInterfaces = ["tailscale0"];
      extraCommands = ''
        iptables -t nat -A POSTROUTING -s ${network.tailscale.network} -o ${externalIf} -j MASQUERADE
      '';
      extraStopCommands = ''
        iptables -t nat -D POSTROUTING -s ${network.tailscale.network} -o ${externalIf} -j MASQUERADE 2>/dev/null || true
      '';
    };
  };

  # ===========================================================================
  # Tailscale autoconnect
  # ===========================================================================
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    after = ["network-online.target" "tailscale.service"];
    wants = ["network-online.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.tailscale pkgs.jq pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    script = ''
      SECRET=$(cat "${clientSecret}")
      tailscale up --reset --authkey="$SECRET" --ssh --netfilter-mode=nodivert --advertise-exit-node
    '';
  };

  # ===========================================================================
  # systemd-networkd
  # ===========================================================================
  systemd.network = {
    netdevs =
      {
        "10-vmbr0" = {
          netdevConfig = {
            Name = externalIf;
            Kind = "bridge";
          };
          bridgeConfig.VLANFiltering = true;
        };

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

    networks =
      {
        "05-physical" = {
          matchConfig.Name = "enp1s0";
          networkConfig.Bridge = externalIf;
          linkConfig.RequiredForOnline = "carrier";
        };

        "10-vmbr0" = {
          matchConfig.Name = externalIf;
          vlan = ["vlan10" "vlan20"];
          address = ["${network.wan.host}/${toString network.wan.prefixLength}"];
          networkConfig = {
            Gateway = network.wan.gateway;
            DNS = network.dns;
            IPv4Forwarding = true;
            IPv6Forwarding = false;
          };
          bridgeVLANs = [
            {VLAN = mgmtVlanId;}
            {VLAN = svcVlanId;}
          ];
          linkConfig.RequiredForOnline = "carrier";
        };

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
