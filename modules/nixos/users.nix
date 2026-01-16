# User accounts configuration
{
  lib,
  pkgs,
  config,
  homelabConfig,
  sshPublicKey ? "",
  ...
}: let
  userName = homelabConfig.username;
  sshKeys = lib.optional (sshPublicKey != "") sshPublicKey;
  rootPasswordPath = config.sops.secrets.rootPassword.path;
  userPasswordPath = config.sops.secrets."${userName}Password".path;
in {
  sops.secrets = builtins.listToAttrs (map (k: {
      name = k; # Nix 내부 이름 (예: rootPassword, limjihoonPassword)
      value = {
        key = "users/${k}"; # YAML 파일 내 경로 (users/rootPassword)
        neededForUsers = true;
      };
    }) [
      "rootPassword"
      "${userName}Password"
    ]);

  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users = {
      # WARNING:
      # LEAVE '.path' eval here
      # since sops-nix eval won't happen in let section
      # sops-nix will be fail to eval secret
      root = {
        # hashedPasswordFile = config.sops.secrets.rootPassword.path;
        hashedPasswordFile = rootPasswordPath;
        openssh.authorizedKeys.keys = sshKeys;
      };

      "${userName}" = {
        shell = pkgs.zsh;
        isNormalUser = true;
        description = "Limjihoon";
        extraGroups = ["networkmanager" "wheel" "libvirtd"];
        # hashedPasswordFile = config.sops.secrets."${userName}Password".path;
        hashedPasswordFile = userPasswordPath;
        openssh.authorizedKeys.keys = sshKeys;
      };
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
