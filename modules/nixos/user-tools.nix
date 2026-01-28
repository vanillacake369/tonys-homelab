# NixOS user tools configuration
# HM utils.nix + file-explorer.nix 대체
{
  pkgs,
  data,
  ...
}: {
  programs.git = {
    enable = true;
    config = {
      user.name = data.users.git.userName;
      user.email = data.users.git.userEmail;
    };
  };

  environment.systemPackages = with pkgs; [
    yazi
    fzf
    zsh-powerlevel10k
  ];
}
