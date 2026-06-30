{
  config,
  pkgs,
  ...
}: {
  users.mutableUsers = false;
  users.defaultUserShell = pkgs.fish;

  sops.secrets."users/rootPassword" = {
    neededForUsers = true;
  };
  users.users.root.hashedPasswordFile = config.sops.secrets."users/rootPassword".path;
}
