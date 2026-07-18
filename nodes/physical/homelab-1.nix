# Node: homelab-1 (Physical Host)
{
  config,
  lib,
  pkgs,
  ...
}: let
  network = import ../../network/topology.nix;
  externalIf = "vmbr0";
  vlans = network.vlans;
  hostVlans = network.hosts.homelab-1.vlans;
  mgmtVlanId = vlans.management.id;
  svcVlanId = vlans.services.id;

  # libvirt VM 인프라 (pure function — 값은 여기서 주입)
  libvirtInfra = import ../../lib/mk-libvirt.nix {
    inherit lib pkgs;
    vms = network.vmsForHost "homelab-1";
    bridge = externalIf;
    vlanId = svcVlanId;
  };

  clientSecret = config.sops.secrets."tailscale/clientSecret".path;
in {
  imports = [
    ../interface.nix
    ../roles/common.nix
    ../../atoms/user/limjihoon.nix
    ../../atoms/system/git.nix
    ../../atoms/network/ssh-client.nix
    ./disko-config-homelab-1.nix
  ];

  node = {
    ip = network.wan.host;
    role = "host";
    hostType = "physical";
    user = "limjihoon";
  };

  # ===========================================================================
  # libvirt (QEMU/KVM)
  # ===========================================================================
  virtualisation.libvirtd = {
    enable = true;
    qemu.runAsRoot = true;
  };

  environment.systemPackages = with pkgs; [
    virt-manager
    tailscale
  ];

  # VM Domain 자동 정의 + VLAN hook (mk-libvirt.nix 주입)
  # Tailscale autoconnect 과 함께 처리
  systemd.services =
    libvirtInfra.domainServices
    // {
      tailscale-autoconnect = {
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
          tailscale up --reset --authkey="$SECRET" --netfilter-mode=nodivert --advertise-exit-node
        '';
      };
    };

  systemd.tmpfiles.rules = libvirtInfra.hookRules;

  # ===========================================================================
  # Tailscale
  # ===========================================================================
  sops.secrets."tailscale/clientSecret" = {};

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--netfilter-mode=nodivert"
      "--advertise-exit-node"
    ];
  };

  # ===========================================================================
  # 네트워크
  # ===========================================================================
  networking = {
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
  # systemd-networkd (브리지, VLAN — TAP은 libvirt가 관리)
  # ===========================================================================
  systemd.network = {
    netdevs = {
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
    };

    networks = {
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
        address = ["${hostVlans.management.gateway}/${toString vlans.management.prefixLength}"];
        networkConfig.IPv4Forwarding = true;
      };
      "30-vlan20" = {
        matchConfig.Name = "vlan20";
        address = ["${hostVlans.services.gateway}/${toString vlans.services.prefixLength}"];
        networkConfig.IPv4Forwarding = true;
      };
    };
  };
}
