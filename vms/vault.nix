{
  pkgs,
  data,
  ...
}: let
  vmInfo = data.vms.definitions.vault;
in {
  imports = [
    ../modules/profiles/vm-base.nix
    ../modules/profiles/vm-persistent.nix
    ../modules/profiles/vm-common.nix
  ];

  # Vault service
  services.vault = {
    enable = true;
    address = "0.0.0.0:${toString vmInfo.ports.api}";
    storageBackend = "file";
    storagePath = vmInfo.storage.mountPoint;
  };

  # Firewall configuration
  networking.firewall.allowedTCPPorts = builtins.attrValues vmInfo.ports;

  # Vault-specific packages
  environment.systemPackages = with pkgs; [
    vault
  ];
}
