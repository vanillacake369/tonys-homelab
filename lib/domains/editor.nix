# Editor Domain
# Pure data: editor configuration
# No dependencies on other domains
{
  # Default editor
  default = "nvim";

  # Neovim configuration
  neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    # Plugin names (actual plugins resolved by adapter)
    plugins = ["LazyVim"];
  };

  # Vim configuration (fallback)
  vim = {
    enable = true;
  };
}
