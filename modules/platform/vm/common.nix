# Common VM configuration (Users, SSH, Shell)
{
  lib,
  pkgs,
  data,
  specialArgs,
  ...
}: let
  injectedSshPubKey = specialArgs.sshPublicKey or "";
  authorizedKeys =
    data.hosts.definitions.${data.hosts.default}.authorizedKeys
    ++ lib.optional (injectedSshPubKey != "") injectedSshPubKey;
  vmSecretsPath = specialArgs.vmSecretsPath or "/run/host-secrets";
in {
  # Root user configuration
  users.mutableUsers = false;
  users.users.root = {
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = authorizedKeys;
    hashedPasswordFile = "${vmSecretsPath}/users/rootPassword";
  };

  programs.zsh.enable = lib.mkForce true;

  # Standard packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
  ];
}
