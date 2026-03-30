{
  pkgs,
  data,
  ...
}: let
  vmInfo = data.vms.definitions.jenkins;
in {
  imports = [
    ../modules/profiles/vm-base.nix
    ../modules/profiles/vm-persistent.nix
    ../modules/profiles/vm-common.nix
  ];

  microvm.shares = [
    {
      # Share Nix store for faster builds
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag = "nix-store";
      proto = "virtiofs";
    }
  ];

  # Jenkins service
  services.jenkins = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = vmInfo.ports.web;
    withCLI = true;
  };

  # Firewall configuration
  networking.firewall.allowedTCPPorts = builtins.attrValues vmInfo.ports;

  # Packages for CI/CD pipeline
  environment.systemPackages = with pkgs; [
    docker
    kubectl
    nix
  ];

  # Enable Docker for container builds
  virtualisation.docker.enable = true;
}
