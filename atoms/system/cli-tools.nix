# Atoms: Essential CLI Tools
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    busybox
    wget
    curl
    rsync
    ripgrep
    bat
    fd
    eza
    htop
    btop
    jq
    yq
    tree
    zip
    unzip
    killall
  ];
}
