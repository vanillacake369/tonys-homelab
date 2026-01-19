# Home-manager editor configuration
{pkgs, ...}: {
  # Editor packages
  home.packages = with pkgs; [
    vim
  ];

  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [LazyVim];
  };
}
