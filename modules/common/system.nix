# Unified System Common Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.common;
in {
  options.my.common = {
    terminal.enable = lib.mkEnableOption "Terminal tools (zsh, starship, etc)";
    monitoring.enable = lib.mkEnableOption "Monitoring tools (htop, btop)";
    network.enable = lib.mkEnableOption "Network tools (iproute2, dnsutils)";
    dev.enable = lib.mkEnableOption "Development tools (git, gcc, etc)";
    editor.enable = lib.mkEnableOption "Editor (vim, neovim)";
    hardware.enable = lib.mkEnableOption "Hardware/GPU diagnostic tools";
    virtualization.enable = lib.mkEnableOption "Virtualization tools (docker, podman)";
  };

  config = {
    # Base packages (always installed)
    environment.systemPackages = with pkgs;
      [
        wget
        curl
        rsync
        pciutils
        usbutils
        killall
        which
        file
        tree
        zip
        unzip
      ]
      ++ lib.optionals cfg.terminal.enable [
        starship
        eza
        fd
        ripgrep
        bat
        zsh
      ]
      ++ lib.optionals cfg.monitoring.enable [
        htop
        btop
        iotop
        iftop
      ]
      ++ lib.optionals cfg.network.enable [
        iproute2
        dnsutils
        nmap
        mtr
        ethtool
      ]
      ++ lib.optionals cfg.dev.enable [
        git
        gh
        gcc
        gnumake
        jq
        yq
      ]
      ++ lib.optionals cfg.editor.enable [
        vim
      ]
      ++ lib.optionals cfg.hardware.enable [
        lshw
        mesa-demos
        vulkan-tools
        amdgpu_top
        libva-utils
      ]
      ++ lib.optionals cfg.virtualization.enable [
        docker
        containerd
      ];

    programs.zsh.enable = cfg.terminal.enable;
  };
}
