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
  };
  security.sudo.wheelNeedsPassword = false;
}
