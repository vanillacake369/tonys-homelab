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
    terminal.enable = lib.mkEnableOption "Terminal tools (fish, starship, etc)";
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
        fish
        fishPlugins.bass
        fishPlugins.done
        fishPlugins.tide
        fzf
        bat
        ripgrep
        fd
        eza
        zoxide
        direnv
        nix-direnv
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
        netplan
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
    programs = {
      fish = {
        inherit (cfg.terminal) enable;

        shellAliases = {
          ll = "ls -l";
          cat = "bat --style=plain --paging=never";
          grep = "rg";
          clear = "clear -x";
          k = "kubectl";
          m = "minikube";
          kctx = "kubectx";
          ka = "kubectl get all -o wide";
          ks = "kubectl get services -o wide";
          kap = "kubectl apply -f ";
        };

        interactiveShellInit = ''
          # --- Functions ---
          function gitlog
            git log --oneline | fzf --preview 'git show --color=always {1}'
          end

          function pslog
            ps axo pid,rss,comm --no-headers | fzf --preview 'ps o args {1}; ps mu {1}'
          end

          function kube-manifest
            kubectl get $argv -o name | \
              fzf --preview 'kubectl get {} -o yaml' \
                  --bind "ctrl-r:reload(kubectl get $argv -o name)" \
                  --bind "ctrl-i:execute(kubectl edit {+})" \
                  --header 'Ctrl-I: live edit | Ctrl-R: reload list'
          end

          # --- Base Init ---
          set -g fish_greeting
          fish_add_path --move --prepend ${pkgs.fzf}/bin

          # Zellij completion
          if command -v zellij > /dev/null
            ${pkgs.zellij}/bin/zellij setup --generate-completion fish | source
          end

          # Key Bindings
          bind \e\[H beginning-of-line
          bind \e\[F end-of-line

          # Syntax Highlighting Colors
          set -g fish_color_command green
          set -g fish_color_error red --bold
          set -g fish_color_param blue
          set -g fish_color_quote yellow
          set -g fish_color_redirection cyan
          set -g fish_color_end white
        '';
      };
      direnv.enable = true;
      direnv.nix-direnv.enable = true;
      neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
      };
      git = {
        enable = true;
      };
      yazi = {
        enable = true;
      };
    };

    system.activationScripts.tide-setup = {
      text = ''
        if [ ! -f /etc/tide_configured ]; then
          # 시스템 레벨에서 fish를 실행하여 tide를 설정하는 것은 복잡하므로
          # 보통은 사용자가 처음 로그인할 때 실행하도록 권장합니다.
          touch /etc/tide_configured
        fi
      '';
    };
  };
}
