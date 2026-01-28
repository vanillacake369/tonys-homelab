# NixOS user tools configuration
# git, yazi, fzf 등 사용자 유틸리티
{
  pkgs,
  ...
}: {
  programs.git = {
    enable = true;
    config = {
      user.name = "limjihoon";
      user.email = "lonelynight1026@gmail.com";
    };
  };

  environment.systemPackages = with pkgs; [
    yazi
    fzf
    zsh-powerlevel10k
  ];
}
