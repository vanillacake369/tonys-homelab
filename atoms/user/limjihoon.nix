{
  pkgs,
  config,
  ...
}: {
  sops.secrets."users/limjihoonPassword" = {
    neededForUsers = true;
  };

  users.users.limjihoon = {
    isNormalUser = true;
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets."users/limjihoonPassword".path;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcONXeiPvvYoH/EYMU8y2EUjVRPjhL/QfNiI7n6iy9u limjihoon@tonys-mac.local"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
}
