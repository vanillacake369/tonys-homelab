# NixOS shell configuration (호스트 + VM 공통)
# oh-my-zsh, powerlevel10k, fzf, zsh-autoenv를 interactiveShellInit으로 로드
{
  lib,
  pkgs,
  ...
}: let
  aliases = {
    ll = "ls -l";
    cat = "bat --style=plain --paging=never";
    grep = "rg";
    clear = "clear -x";
    k = "kubectl";
    m = "minikube";
    kctx = "kubectx";
    kns = "kubens";
    ka = "kubectl get all -o wide";
    ks = "kubectl get services -o wide";
    kap = "kubectl apply -f ";
  };

  functions = {
    kube-manifest = ''
      kube-manifest() {
        kubectl get $* -o name | \
            fzf --preview 'kubectl get {} -o yaml' \
                --bind "ctrl-r:reload(kubectl get $* -o name)" \
                --bind "ctrl-i:execute(kubectl edit {+})" \
                --header 'Ctrl-I: live edit | Ctrl-R: reload list';
      }
    '';
    gitlog = ''
      gitlog() {
        (
          git log --oneline | fzf --preview 'git show --color=always {1}'
        )
      }
    '';
    pslog = ''
      pslog() {
        (
          ps axo pid,rss,comm --no-headers | fzf --preview 'ps o args {1}; ps mu {1}'
        )
      }
    '';
    search = ''
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

  functionsLinux = {
    systemdlog = ''
      systemdlog() {
        (
          find /etc/systemd/system/ -name "*.service" | \
            fzf --preview 'cat {}' \
                --bind "ctrl-i:execute(nvim {})" \
                --bind "ctrl-s:execute(cat {} | xclip -selection clipboard)"
        )
      }
    '';
  };

  ohmyzshPlugins = ["git" "kubectl" "kube-ps1"];

  allFunctions = builtins.concatStringsSep "\n" (builtins.attrValues functions);
  linuxFunctions = builtins.concatStringsSep "\n" (builtins.attrValues functionsLinux);
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = aliases;
    interactiveShellInit = ''
      # =============================================================================
      # Oh-My-Zsh
      # =============================================================================
      export ZSH=${pkgs.oh-my-zsh}/share/oh-my-zsh
      plugins=(${builtins.concatStringsSep " " ohmyzshPlugins})
      source $ZSH/oh-my-zsh.sh

      # =============================================================================
      # Powerlevel10k
      # =============================================================================
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

      # =============================================================================
      # zsh-autoenv
      # =============================================================================
      source ${pkgs.zsh-autoenv}/share/zsh-autoenv/autoenv.zsh

      # =============================================================================
      # FZF
      # =============================================================================
      if [[ -f "${pkgs.fzf}/share/fzf/key-bindings.zsh" ]]; then
        source "${pkgs.fzf}/share/fzf/key-bindings.zsh"
      fi
      if [[ -f "${pkgs.fzf}/share/fzf/completion.zsh" ]]; then
        source "${pkgs.fzf}/share/fzf/completion.zsh"
      fi
      export FZF_DEFAULT_OPTS="--info=inline --border=rounded --margin=1 --padding=1"

      # =============================================================================
      # Keybindings (Home/End)
      # =============================================================================
      case $TERM in (xterm*)
        bindkey '^[[H' beginning-of-line
        bindkey '^[[F' end-of-line
      esac

      # =============================================================================
      # systemd lingering (Linux only)
      # =============================================================================
      ${lib.optionalString pkgs.stdenv.isLinux ''
        if [[ "$USER" != "root" ]] && ! loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
          loginctl enable-linger "$USER" 2>/dev/null || true
        fi
      ''}

      # =============================================================================
      # Custom Functions
      # =============================================================================
      ${allFunctions}
      ${lib.optionalString pkgs.stdenv.isLinux linuxFunctions}
    '';
  };

  environment.systemPackages = with pkgs; [
    oh-my-zsh
    zsh-powerlevel10k
    zsh-autoenv
    fzf
  ];
}
