# User accounts configuration
{
  pkgs,
  config,
  sshPublicKey ? "",
  ...
}: {
  # SOPS configuration
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
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

  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPasswordFile = config.sops.secrets.root_password.path;
        openssh.authorizedKeys.keys = [sshPublicKey];
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
        openssh.authorizedKeys.keys = [sshPublicKey];
      };
    };
  };

  # Shell configuration
  programs.zsh.enable = true;
  environment.shells = with pkgs; [zsh];

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;
}
