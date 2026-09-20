# Node: homelab-2 (Bare-metal Kubernetes Worker)
{pkgs, ...}: let
  network = import ../../network/topology.nix;

  hostName = "homelab-2";
  host = network.hosts.${hostName};

  uplinkAddress = "${host.uplink.ip}/${toString host.uplink.prefixLength}";
in {
  imports = [
    ../interface.nix
    ../roles/k8s-worker.nix
    ../../atoms/user/limjihoon.nix
    ../../atoms/system/git.nix
    ../../atoms/system/always-on-laptop.nix
    ../../atoms/network/tailscale.nix
    ../../atoms/network/ssh-client.nix
    ./disko-config-homelab-2.nix
  ];

  node = {
    ip = host.uplink.ip;
    role = host.role;
    hostType = "physical";
    user = host.user;
  };

  # LG 15UD780-PX50K / Intel i5-8250U / UHD 620.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
    graphics.enable = true;
  };

  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    pciutils
    usbutils
  ];

  systemd.network = {
    networks = {
      "05-uplink" = {
        matchConfig.Name = host.uplink.interface;
        address = [uplinkAddress];
        networkConfig = {
          Gateway = host.uplink.gateway;
          DNS = network.dns;
        };
        linkConfig.RequiredForOnline = "routable";
      };
    };
  };
}
