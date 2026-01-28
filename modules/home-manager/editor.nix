# Home-manager editor configuration
# Domain-driven: imports editor configuration from lib/domains/editor.nix
{pkgs, ...}: let
  # Import editor domain directly
  editorDomain = import ../../lib/domains/editor.nix;
in {
  # Editor packages (vim as fallback)
  home.packages = with pkgs;
    (if editorDomain.vim.enable then [vim] else []);

  # Neovim configuration from domain
  programs.neovim = {
    enable = editorDomain.neovim.enable;
    defaultEditor = editorDomain.neovim.defaultEditor;
    viAlias = editorDomain.neovim.viAlias;
    vimAlias = editorDomain.neovim.vimAlias;
    vimdiffAlias = editorDomain.neovim.vimdiffAlias;
    plugins = with pkgs.vimPlugins; [LazyVim];
  };
}
