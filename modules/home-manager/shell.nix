# Home-manager shell configuration
# Domain-driven: imports shell configuration from lib/domains/shell.nix
{
  lib,
  pkgs,
  ...
}: let
  # Import shell domain directly (home-manager doesn't receive specialArgs.domains)
  shellDomain = import ../../lib/domains/shell.nix;

  # Combine all functions from domain
  allFunctions = builtins.concatStringsSep "\n" (builtins.attrValues shellDomain.functions);

  # Platform-specific functions
  platformFunctions =
    if pkgs.stdenv.isDarwin
    then builtins.concatStringsSep "\n" (builtins.attrValues (shellDomain.functionsDarwin or {}))
    else if pkgs.stdenv.isLinux
    then builtins.concatStringsSep "\n" (builtins.attrValues (shellDomain.functionsLinux or {}))
    else "";

  # Platform-specific aliases (additions to domain aliases)
  platformAliases = {
    # Tools
    claude-monitor = "uv tool run claude-monitor";

    # Clipboard (platform-specific)
    copy =
      if pkgs.stdenv.isDarwin
      then "pbcopy"
      else "xclip -selection clipboard";
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    hidden-bar = "open ~/.nix-profile/Applications/\"Hidden Bar.app\"";
  };
in {
  # Shell packages
  home.packages = with pkgs; [
    zsh-autoenv
    zsh-powerlevel10k
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # Shell aliases from domain + platform-specific
      shellAliases = shellDomain.aliases // platformAliases;

      # Powerlevel10k theme
      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];

      # Oh-My-Zsh plugins from domain
      oh-my-zsh = {
        enable = true;
        plugins = shellDomain.zsh.ohMyZsh.plugins;
      };

      # ZSH initialization script
      initContent = ''

        # Nix daemon initialization (prevents removal via macOS updates)
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
          source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi

        # Powerlevel10k instant prompt
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi

        # Apply zsh-autoenv
        source ${pkgs.zsh-autoenv}/share/zsh-autoenv/autoenv.zsh

        # Apply powerlevel10k theme
        source ~/.p10k.zsh

        # Enable Home/End keys
        case $TERM in (xterm*)
        bindkey '^[[H' beginning-of-line
        bindkey '^[[F' end-of-line
        esac

        # Enable systemd user session lingering (Linux only)
        ${lib.optionalString pkgs.stdenv.isLinux ''
          if ! loginctl show-user "$USER" | grep -q "Linger=yes"; then
            loginctl enable-linger "$USER"
          fi
        ''}

        # =============================================================================
        # Custom Functions (from domain)
        # =============================================================================
        ${allFunctions}

        # Platform-specific functions
        ${platformFunctions}

        # Package dependencies viewer (apt-specific, not in domain)
        pckg-dep() {
          (
            apt-cache search . | fzf --preview 'apt-cache depends {1}'
          )
        }
      '';
    };
  };
}
