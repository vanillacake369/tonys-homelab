# Kubernetes Master Node VM
# VLAN 20 (Services)
{
  pkgs,
  homelabConstants,
  vmSecretsPath,
  ...
}: let
  clusterJoinToken = "${vmSecretsPath}/k8s/joinToken";
  vmInfo = homelabConstants.vms.k8s-master;
  vlan = homelabConstants.networks.vlans.${vmInfo.vlan};
in {
  imports = [
    ../modules/nixos/k8s-base.nix
  ];

  # User configuration
  # Password is managed via sops in mk-microvms.nix (mkVmCommonModule)
  users.mutableUsers = false;

  microvm = {
    hypervisor = homelabConstants.common.hypervisor;
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;
    vsock.cid = vmInfo.vsockCid;

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

  # Kubernetes master configuration
  services.kubernetes = {
    roles = ["master"];
    masterAddress = vmInfo.ip;
    apiserverAddress = "https://${vmInfo.ip}:${toString vmInfo.ports.api}";
    flannel.enable = true;
    addons.dns.enable = true;
    easyCerts = true;
    apiserver = {
      enable = true;
      securePort = vmInfo.ports.api;
      advertiseAddress = vmInfo.ip;
      tokenAuthFile = clusterJoinToken;
    };
    scheduler.enable = true;
    controllerManager.enable = true;
  };

  # Master node firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8888 # cfssl
      10250 # kubelet API
      10255 # kubelet read-only
      6443 # API server
      2379 # etcd client
      2380 # etcd peer
      10251 # scheduler (deprecated)
      10252 # controller-manager
      10257 # controller-manager secure
      10259 # scheduler secure
    ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];
  };

  # Set KUBECONFIG for root user
  environment.variables.KUBECONFIG = "/etc/kubernetes/cluster-admin.kubeconfig";

  # Master-specific packages
  environment.systemPackages = with pkgs; [
    etcd
  ];

  system.stateVersion = homelabConstants.common.stateVersion;
}
