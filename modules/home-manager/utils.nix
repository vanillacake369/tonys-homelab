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
    expect
    bridge-utils
    tcpdump
    nftables
    screen
    ngrok
    bind
    lsof
    dmidecode
    usbutils

    # AMD GPU 진단 도구
    amdgpu_top # iGPU 모니터링 및 VBIOS 덤프
  ];
}
