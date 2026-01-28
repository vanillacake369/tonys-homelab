# Kubernetes Worker 1 VM (with GPU passthrough capability)
# VLAN 20 (Services)
{
  homelabConstants,
  vmSecretsPath,
  pkgs,
  ...
}: let
  clusterJoinToken = "${vmSecretsPath}/k8s/joinToken";
  vmInfo = homelabConstants.vms.k8s-worker-1;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
  masterInfo = homelabConstants.vms.k8s-master;
in {
  imports = [
    ../modules/nixos/k8s-base.nix
  ];

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
  # Password is managed via sops in mk-microvms.nix (mkVmCommonModule)
  users.mutableUsers = false;

  microvm = {
    hypervisor = homelabConstants.common.hypervisor;
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;

    # Note: k8s-worker-1 does not use vsock (GPU passthrough configuration)
    # GPU PCI passthrough configuration (uncomment and adjust after `lspci | grep VGA`)
    # qemu.extraArgs = [
    #   "-device" "vfio-pci,host=00:02.0"  # Intel iGPU example
    # ];

    interfaces = [
      {
        type = "tap";
        id = vmInfo.tapId;
        mac = vmInfo.mac;
      }
    ];
  };

  # Network configuration (systemd-networkd)
  networking = {
    hostName = vmInfo.hostname;
    useDHCP = false;
    nameservers = homelabConstants.networks.dns;
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = ["${vmInfo.ip}/${toString vlan.prefixLength}"];
    gateway = [vlan.gateway];
    dns = homelabConstants.networks.dns;
    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = false;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Kubernetes worker configuration
  services.kubernetes = {
    roles = ["node"];
    masterAddress = masterInfo.ip;
    apiserverAddress = "https://${masterInfo.ip}:${toString masterInfo.ports.api}";
    easyCerts = true;
  };

  # Worker node firewall configuration
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

  system.stateVersion = homelabConstants.common.stateVersion;
}
