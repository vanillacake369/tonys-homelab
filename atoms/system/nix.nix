# Atoms: Nix Global Settings
{lib, ...}: {
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = lib.mkDefault true;
      trusted-users = ["root" "@wheel"];
    };
    gc = {
      automatic = lib.mkDefault true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    optimise.automatic = lib.mkDefault true;
  };
}
