# User accounts configuration
{
  lib,
  pkgs,
  config,
  sshPublicKey ? "",
  ...
}: {
  # SOPS configuration
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    # Use SSH host key for decryption
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    # Define secrets (passwords only)
    secrets = {
      root_password = {
        neededForUsers = true;
      };
      limjihoon_password = {
        neededForUsers = true;
      };
    };
  };

  # Enable zsh system-wide
  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPasswordFile = config.sops.secrets.root_password.path;
        openssh.authorizedKeys.keys = lib.optional (sshPublicKey != "") sshPublicKey;
      };
      limjihoon = {
        isNormalUser = true;
        shell = pkgs.zsh;
        description = "Limjihoon";
        extraGroups = [
          "networkmanager"
          "wheel"
          "libvirtd"
        ];
        hashedPasswordFile = config.sops.secrets.limjihoon_password.path;
        openssh.authorizedKeys.keys = lib.optional (sshPublicKey != "") sshPublicKey;
      };
    };
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;
}
