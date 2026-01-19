# Home-manager shell configuration
{
  lib,
  pkgs,
  ...
}: {
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

      # Shell aliases
      shellAliases =
        {
          # Basic utilities
          ll = "ls -l";
          cat = "bat --style=plain --paging=never";
          grep = "rg";
          clear = "clear -x";

          # Kubernetes shortcuts
          k = "kubectl";
          m = "minikube";
          kctx = "kubectx";
          kns = "kubens";
          ka = "kubectl get all -o wide";
          ks = "kubectl get services -o wide";
          kap = "kubectl apply -f ";

          # Tools
          claude-monitor = "uv tool run claude-monitor";

          # Clipboard (platform-specific)
          copy =
            if pkgs.stdenv.isDarwin
            then "pbcopy"
            else "xclip -selection clipboard";
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin {
          hidden-bar = "open ~/.nix-profile/Applications/\"Hidden Bar.app\"";
        };

      # Powerlevel10k theme
      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];

      # Oh-My-Zsh plugins
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "kubectl"
          "kube-ps1"
        ];
      };

      # ZSH initialization script
      # `programs.zsh.initContent`
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

        # Load home-manager session variables (NixOS module handles this automatically)
        # For standalone Home-Manager, uncomment the following line:
        # . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"

        # Enable systemd user session lingering (Linux only)
        ${lib.optionalString pkgs.stdenv.isLinux ''
          if ! loginctl show-user "$USER" | grep -q "Linger=yes"; then
            loginctl enable-linger "$USER"
          fi
        ''}

        # =============================================================================
        # Custom Functions
        # =============================================================================

        # Kubernetes manifest viewer with fzf
        kube-manifest() {
          kubectl get $* -o name | \
              fzf --preview 'kubectl get {} -o yaml' \
                  --bind "ctrl-r:reload(kubectl get $* -o name)" \
                  --bind "ctrl-i:execute(kubectl edit {+})" \
                  --header 'Ctrl-I: live edit | Ctrl-R: reload list';
        }

        # Git log with preview
        gitlog() {
          (
            git log --oneline | fzf --preview 'git show --color=always {1}'
          )
        }

        # Process viewer
        pslog() {
          (
            ps axo pid,rss,comm --no-headers | fzf --preview 'ps o args {1}; ps mu {1}'
          )
        }

        # Package dependencies viewer
        pckg-dep() {
          (
            apt-cache search . | fzf --preview 'apt-cache depends {1}'
          )
        }

        # Systemd service viewer (Linux)
        ${lib.optionalString pkgs.stdenv.isLinux ''
          systemdlog() {
            (
              find /etc/systemd/system/ -name "*.service" | \
                fzf --preview 'cat {}' \
                    --bind "ctrl-i:execute(nvim {})" \
                    --bind "ctrl-s:execute(cat {} | copy)"
            )
          }
        ''}

        # Launchd service viewer (macOS)
        ${lib.optionalString pkgs.stdenv.isDarwin ''
          systemdlog() {
            (
              launchctl list | \
                fzf --preview 'launchctl print system/{1} 2>/dev/null || launchctl print user/$(id -u)/{1} 2>/dev/null || echo "Service details not available"' \
                    --bind "ctrl-i:execute(nvim /Library/LaunchDaemons/{1}.plist 2>/dev/null || nvim /System/Library/LaunchDaemons/{1}.plist 2>/dev/null || nvim ~/Library/LaunchAgents/{1}.plist 2>/dev/null || echo 'Plist file not found')" \
                    --bind "ctrl-s:execute(launchctl print system/{1} 2>/dev/null | pbcopy || launchctl print user/$(id -u)/{1} 2>/dev/null | pbcopy)" \
                    --header 'Ctrl-I: edit plist | Ctrl-R: reload list | Ctrl-S: copy service info'
            )
          }
        ''}

        # Search files by keyword with fzf
        search() {
          [[ $# -eq 0 ]] && { echo "provide regex argument"; return }
          local matching_files
          case $1 in
            -h)
              shift
              matching_files=$(rg -l --hidden $1 | fzf --exit-0 --preview="rg --color=always -n -A 20 '$1' {} ")
              ;;
            *)
              matching_files=$(rg -l -- $1 | fzf --exit-0 --preview="rg --color=always -n -A 20 -- '$1' {} ")
              ;;
          esac
          [[ -n "$matching_files" ]] && $EDITOR "$matching_files" -c/$1
        }
      '';
    };
  };
}
