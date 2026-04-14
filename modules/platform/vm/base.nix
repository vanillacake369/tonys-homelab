# modules/platform/vm/base.nix
# The "Super-Base" Profile for all MicroVMs
{
  config,
  lib,
  pkgs,
  data,
  microvmTarget,
  specialArgs,
  ...
}: let
  vmName = microvmTarget;
  vmInfo = data.vms.definitions.${vmName};
  vlanInfo = data.network.vlans.${vmInfo.vlan};

  # SSH & Secrets Handling
  injectedSshPubKey = specialArgs.sshPublicKey or "";
  authorizedKeys =
    data.hosts.definitions.${data.hosts.default}.authorizedKeys
    ++ lib.optional (injectedSshPubKey != "") injectedSshPubKey;
  vmSecretsPath = specialArgs.vmSecretsPath or "/run/host-secrets";
in {
  imports = [
    ../../common/system.nix # Option definitions (my.common.*)
  ];

  # ------------------------------------------------------------
  # 1. Hardware & Networking (Data-Driven)
  # ------------------------------------------------------------
  microvm = {
    vcpu = lib.mkDefault vmInfo.vcpu;
    mem = lib.mkDefault vmInfo.mem;
    vsock.cid = lib.mkDefault vmInfo.vsockCid;
    interfaces = [
      {
        type = "tap";
        id = vmInfo.tapId;
        mac = vmInfo.mac;
      }
    ];
  };

  networking = {
    hostName = lib.mkForce vmInfo.hostname;
    useDHCP = false;
    nameservers = data.network.dns;
    firewall.enable = lib.mkDefault true;
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = ["${vmInfo.ip}/${toString vlanInfo.prefixLength}"];
    gateway = [vlanInfo.gateway];
    dns = data.network.dns;
    networkConfig.IPv4Forwarding = true;
    linkConfig.RequiredForOnline = "no";
  };

  # ------------------------------------------------------------
  # 2. Identity & Access
  # ------------------------------------------------------------
  users.mutableUsers = false;
  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = authorizedKeys;
    hashedPasswordFile = "${vmSecretsPath}/users/rootPassword";
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Standard packages for every VM
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
  ];

  # ------------------------------------------------------------
  # 3. System Defaults
  # ------------------------------------------------------------
  programs.zsh.enable = lib.mkForce true;
  system.stateVersion = data.hosts.common.stateVersion;
}
