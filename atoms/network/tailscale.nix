# Atom: Tailscale node membership
{
  config,
  pkgs,
  ...
}: {
  sops.secrets."tailscale/clientSecret" = {};

  environment.systemPackages = with pkgs; [
    tailscale
  ];

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale/clientSecret".path;
    extraUpFlags = [
      "--netfilter-mode=nodivert"
      "--ssh"
    ];
    extraSetFlags = [
      "--ssh"
    ];
  };

  networking.firewall = {
    allowedUDPPorts = [config.services.tailscale.port];
    trustedInterfaces = ["tailscale0"];
  };
}
