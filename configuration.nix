# Main Host Configuration (Physical Server)
{
  config,
  pkgs,
  data,
  ...
}: {
  imports = [
    ./modules/platform/host/boot.nix
    ./modules/platform/host/locale.nix
    ./modules/platform/host/network.nix
    ./modules/platform/host/nix-settings.nix
    ./modules/platform/host/ssh.nix
    ./modules/platform/host/users.nix
    ./modules/platform/host/user-tools.nix
    ./modules/platform/host/microvm-storage.nix
    ./modules/platform/host/tailscale.nix
    ./modules/platform/host/amdgpu.nix
    ./disko-config.nix
  ];

  # Enable unified common modules for host
  my.common = {
    terminal.enable = true;
    monitoring.enable = true;
    network.enable = true;
    dev.enable = true;
    editor.enable = true;
    hardware.enable = true;
    virtualization.enable = true;
  };

  # SSH public key for root (from data)
  users.users.root.openssh.authorizedKeys.keys = [
    data.hosts.definitions.homelab.sshPubKey
  ];

  system.stateVersion = data.hosts.common.stateVersion;
}
