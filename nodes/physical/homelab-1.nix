# Node: homelab-1 (Physical Host)
{
  lib,
  pkgs,
  ...
}: let
  network = import ../../network/topology.nix;
  projections = import ../../network/projections.nix {topology = network;};

  hostName = "homelab-1";
  host = network.hosts.${hostName};

  externalIf = "vmbr0";
  vlans = network.vlans;
  mgmtVlanId = vlans.management.id;
  svcVlanId = vlans.services.id;
  mgmtIf = "vlan${toString mgmtVlanId}";
  svcIf = "vlan${toString svcVlanId}";
  uplinkAddress = "${host.uplink.ip}/${toString host.uplink.prefixLength}";

  # libvirt VM 인프라 (pure function — 값은 여기서 주입)
  libvirtInfra = import ../../lib/mk-libvirt.nix {
    inherit lib pkgs;
    vms = projections.vmsForHost hostName;
    bridge = externalIf;
    vlanId = svcVlanId;
  };
in {
  imports = [
    ../interface.nix
    ../profiles/base.nix
    ../../atoms/user/limjihoon.nix
    ../../atoms/system/git.nix
    ../../atoms/network/tailscale.nix
    ../../atoms/network/ssh-client.nix
    ./disko-config-homelab-1.nix
  ];

  node = {
    ip = host.uplink.ip;
    role = host.role;
    hostType = "physical";
    user = host.user;
  };

  # ===========================================================================
  # libvirt (QEMU/KVM)
  # ===========================================================================
  virtualisation.libvirtd = {
    enable = true;
    qemu.runAsRoot = true;
  };

  # Host-owned accelerator stack for the SER8 Ryzen 8845HS / Radeon 780M.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    graphics.enable = true;
    amdgpu.opencl.enable = true;
  };

  users.users.limjihoon.extraGroups = [
    "render"
    "video"
    "libvirtd"
    "kvm"
  ];

  environment.systemPackages = with pkgs; [
    virt-manager
    amdgpu_top
    clinfo
    libva-utils
    radeontop
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    vulkan-tools
  ];

  # VM Domain 자동 정의 + VLAN hook (mk-libvirt.nix 주입)
  systemd.services = libvirtInfra.domainServices;

  systemd.tmpfiles.rules = libvirtInfra.hookRules;

  # ===========================================================================
  # Tailscale
  # ===========================================================================
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  services.tailscale.extraUpFlags = [
    "--advertise-exit-node"
  ];

  # ===========================================================================
  # 네트워크
  # ===========================================================================
  networking = {
    nat = {
      enable = true;
      externalInterface = externalIf;
      internalInterfaces = [mgmtIf svcIf];
      enableIPv6 = false;
    };

    firewall = {
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
      "10-${externalIf}" = {
        netdevConfig = {
          Name = externalIf;
          Kind = "bridge";
        };
        bridgeConfig.VLANFiltering = true;
      };

      "20-${mgmtIf}" = {
        netdevConfig = {
          Name = mgmtIf;
          Kind = "vlan";
        };
        vlanConfig.Id = mgmtVlanId;
      };
      "20-${svcIf}" = {
        netdevConfig = {
          Name = svcIf;
          Kind = "vlan";
        };
        vlanConfig.Id = svcVlanId;
      };
    };

    networks = {
      "05-physical" = {
        matchConfig.Name = host.uplink.interface;
        networkConfig.Bridge = externalIf;
        linkConfig.RequiredForOnline = "carrier";
      };

      "10-${externalIf}" = {
        matchConfig.Name = externalIf;
        vlan = [mgmtIf svcIf];
        address = [uplinkAddress];
        networkConfig = {
          Gateway = host.uplink.gateway;
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

      "30-${mgmtIf}" = {
        matchConfig.Name = mgmtIf;
        address = ["${host.vlans.management.address}/${toString vlans.management.prefixLength}"];
        networkConfig.IPv4Forwarding = true;
      };
      "30-${svcIf}" = {
        matchConfig.Name = svcIf;
        address = ["${host.vlans.services.address}/${toString vlans.services.prefixLength}"];
        networkConfig.IPv4Forwarding = true;
      };
    };
  };
}
