# Common VM configuration (Users, SSH, Shell)
{
  lib,
  pkgs,
  data,
  specialArgs,
  ...
}: let
  hostSshPubKey = data.hosts.definitions.${data.hosts.default}.sshPubKey or null;
  vmSecretsPath = specialArgs.vmSecretsPath or "/run/host-secrets";
in {
  # Root user configuration
  users.mutableUsers = false;
  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = lib.optional (hostSshPubKey != null) hostSshPubKey;
    hashedPasswordFile = "${vmSecretsPath}/users/rootPassword";
  };

  programs.zsh.enable = true;

  # Standard packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
  ];
}
