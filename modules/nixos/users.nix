# User accounts configuration
{
  lib,
  pkgs,
  config,
  data,
  sshPublicKey ? "",
  ...
}: let
  userName = data.hosts.definitions.${data.hosts.default}.username;
  sshKeys = lib.optional (sshPublicKey != "") sshPublicKey;
  rootPasswordPath = config.sops.secrets.rootPassword.path;
  userPasswordPath = config.sops.secrets."${userName}Password".path;
in {
  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPasswordFile = rootPasswordPath;
        openssh.authorizedKeys.keys = sshKeys;
      };
      "${userName}" = {
        shell = pkgs.zsh;
        isNormalUser = true;
        description = "Limjihoon";
        extraGroups = ["networkmanager" "wheel" "libvirtd"];
        hashedPasswordFile = userPasswordPath;
        openssh.authorizedKeys.keys = sshKeys;
      };
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
