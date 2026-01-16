# Home-manager utilities configuration
{pkgs, ...}: {
  # Git configuration
  programs.git = {
    settings = {
      user = {
        name = "limjihoon";
        email = "lonelynight1026@gmail.com";
      };
    };
    enable = true;
  };

  # System utilities
  home.packages = with pkgs; [
    git
    pciutils
    ripgrep
    htop
    btop
    zellij
    wget
    psmisc
    strace
    curl
    tree
    ncdu
    neofetch
    bat
    jq
    moreutils
    tree
    expect
  ];
}
