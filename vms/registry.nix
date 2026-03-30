{
  pkgs,
  data,
  ...
}: let
  vmInfo = data.vms.definitions.registry;
in {
  imports = [
    ../modules/profiles/vm-base.nix
    ../modules/profiles/vm-persistent.nix
    ../modules/profiles/vm-common.nix
  ];

  # Docker Registry service
  services.dockerRegistry = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = vmInfo.ports.registry;
    storagePath = vmInfo.storage.mountPoint;
    enableDelete = true;
    enableGarbageCollect = true;
  };

  # Firewall configuration
  networking.firewall.allowedTCPPorts = builtins.attrValues vmInfo.ports;

  environment.systemPackages = with pkgs; [
    docker
  ];
}
