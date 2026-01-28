# NixOS editor configuration
# HM editor.nix 대체
{
  pkgs,
  data,
  ...
}: let
  editorData = data.editor;
in {
  programs.neovim = {
    enable = editorData.neovim.enable;
    defaultEditor = editorData.neovim.defaultEditor;
    viAlias = editorData.neovim.viAlias;
    vimAlias = editorData.neovim.vimAlias;
  };

  environment.systemPackages = with pkgs;
    lib.optional editorData.vim.enable vim;
}
