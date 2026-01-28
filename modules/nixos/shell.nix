# NixOS shell configuration (호스트 + VM 공통)
# HM shell.nix 대체 — NixOS programs.zsh 사용
# oh-my-zsh, powerlevel10k, fzf, zsh-autoenv를 interactiveShellInit으로 로드
{
  lib,
  pkgs,
  data,
  ...
}: let
  shellData = data.shell;
  allFunctions = builtins.concatStringsSep "\n" (builtins.attrValues shellData.functions);
  linuxFunctions = builtins.concatStringsSep "\n" (builtins.attrValues (shellData.functionsLinux or {}));
  ohmyzshPlugins = shellData.zsh.ohMyZsh.plugins;
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = shellData.aliases;
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
      # Instant prompt (캐시된 프롬프트 즉시 표시)
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
