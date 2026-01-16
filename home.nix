{isLinux, ...}: {
  # Enable Home Manager
  programs.home-manager.enable = true;

  # Set env automatically (Linux only)
  targets.genericLinux.enable = isLinux;

  # Home manager config
  home = {
    stateVersion = "24.11";
    username = "limjihoon";
    homeDirectory = "/home/limjihoon";
  };

  # Import existing modules
  imports = [
    ./modules/home-manager/shell.nix
    ./modules/home-manager/editor.nix
    ./modules/home-manager/file-explorer.nix
    ./modules/home-manager/utils.nix
  ];
}
