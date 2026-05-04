{pkgs, ...}: {
  programs.fish = {
    enable = true;

    shellAliases = {
      ll = "ls -l";
      cat = "bat --style=plain --paging=never";
      grep = "rg";
      clear = "clear -x";
      k = "kubectl";
      ka = "kubectl get all -o wide";
      ks = "kubectl get services -o wide";
      kap = "kubectl apply -f ";
    };

    interactiveShellInit = ''
      set -g fish_greeting

      # ========================================================================
      # Tide 프롬프트 자동 부트스트랩 (사용자 요청 방식 + 즉시 반영 v5)
      # ========================================================================
      if status is-interactive
        # 1. Tide 경로 확보
        if not type -q tide
            set -lp fish_function_path ${pkgs.fishPlugins.tide}/share/fish/vendor_functions.d
        end

        # 2. 자동 설정 실행 (v5)
        if type -q tide; and not set -q __nixos_tide_bootstrap_v5
            tide configure \
                --auto \
                --style=Lean \
                --prompt_colors='True color' \
                --show_time=No \
                --lean_prompt_height='Two lines' \
                --prompt_connection=Disconnected \
                --prompt_spacing=Sparse \
                --icons='Many icons' \
                --transient=No >/dev/null 2>&1

            # [핵심] 현재 세션에 즉시 반영
            tide reload >/dev/null 2>&1

            set -U __nixos_tide_bootstrap_v5 applied
        end
      end

      # ========================================================================
      # nvim을 기본 에디터로 설정
      # ========================================================================
      set -gx EDITOR nvim
      set -gx VISUAL nvim
      set -gx KUBE_EDITOR nvim

      # ========================================================================
      # 기타 도구 초기화
      # ========================================================================
      if type -q zoxide; zoxide init fish | source; end
      if type -q direnv; direnv hook fish | source; end
    '';
  };

  environment.systemPackages = with pkgs; [
    fishPlugins.tide
    fishPlugins.bass
    fishPlugins.done
    fzf
    zoxide
    direnv
    nix-direnv
    bat
    ripgrep
  ];
}
