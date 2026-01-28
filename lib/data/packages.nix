# Packages Domain
# Pure data: package groups by category
# No dependencies on other domains
#
# Each group is a function: pkgs -> [packages]
# This allows lazy evaluation and platform-specific filtering
{
  groups = {
    # Core system utilities
    core = p: with p; [
      coreutils
      findutils
      gnugrep
      gnused
    ];

    # Shell enhancement
    shell = p: with p; [
      bat
      ripgrep
      fzf
      jq
      tree
    ];

    # Editors
    editor = p: with p; [
      neovim
      vim
    ];

    # Network utilities
    network = p: with p; [
      curl
      wget
      bind        # dig, nslookup
      tcpdump
      nftables
    ];

    # System monitoring
    monitoring = p: with p; [
      htop
      btop
      ncdu
      lsof
      psmisc      # pstree, killall
    ];

    # Development tools
    dev = p: with p; [
      git
      strace
      moreutils
      expect
    ];

    # Kubernetes tools
    k8s = p: with p; [
      kubectl
      # kubernetes-helm
      # kubectx  # if available
    ];

    # Hardware diagnostics
    hardware = p: with p; [
      pciutils    # lspci
      usbutils    # lsusb
      dmidecode
    ];

    # GPU tools (AMD)
    gpu-amd = p: with p; [
      amdgpu_top
      # rocmPackages.rocm-smi  # if needed
    ];

    # Container/VM tools
    virtualization = p: with p; [
      bridge-utils
    ];

    # Terminal multiplexer
    terminal = p: with p; [
      zellij
      screen
    ];

    # Misc utilities
    misc = p: with p; [
      neofetch
      ngrok
    ];

    # GPU diagnostics (platform-agnostic)
    gpu-diag = p: with p; [
      mesa-demos     # glxinfo
      vulkan-tools   # vulkaninfo
    ];
  };

  # Profile-based package combinations
  # Maps profile name -> list of group names
  profiles = {
    # Minimal: just enough to work
    minimal = ["core" "shell"];

    # Server: basic server administration
    server = ["core" "shell" "editor" "network" "monitoring" "dev" "hardware"];

    # K8s node: server + kubernetes tools
    k8s-node = ["core" "shell" "editor" "network" "monitoring" "k8s" "hardware"];

    # Development: full dev environment
    dev = ["core" "shell" "editor" "network" "monitoring" "dev" "k8s" "terminal"];

    # Full: everything (for main workstation)
    full = ["core" "shell" "editor" "network" "monitoring" "dev" "k8s" "hardware" "gpu-amd" "virtualization" "terminal" "misc" "gpu-diag"];
  };
}
