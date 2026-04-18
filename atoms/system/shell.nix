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

      # Tide 설정이 되어있지 않은 경우 자동 설정 (최초 1회 혹은 변동 시)
      # if not set -q __tide_setup_complete
      #   # 프롬프트 스타일 설정 (Lean style 기반)
      #   set -U tide_character_icon '❯'
      #   set -U tide_character_color 5FD700
      #   set -U tide_context_always_display false
      #   set -U tide_context_color_default D7AF00
      #   set -U tide_context_color_root D75F00
      #   set -U tide_cpu_color 5F875F
      #   set -U tide_cpu_display_threshold 90
      #   set -U tide_direnv_color D7AF00
      #   set -U tide_direnv_display_possibility true
      #   set -U tide_git_color_branch 5FD700
      #   set -U tide_git_color_dirty D75F00
      #   set -U tide_git_color_staged D7AF00
      #   set -U tide_git_color_upstream 5FD700
      #   set -U tide_left_prompt_items context pwd git newline character
      #   set -U tide_right_prompt_items status cmd_duration admin direnv node python rust terraform nix_shell crystal jobs
      #   set -U tide_pwd_color_anchors 00AFFF
      #   set -U tide_pwd_color_dirs 0087AF
      #   set -U tide_pwd_color_truncated_dirs 878787
      #
      #   set -U __tide_setup_complete true
      # end
    '';
  };

  environment.systemPackages = with pkgs; [
    fishPlugins.bass
    fishPlugins.done
    fishPlugins.tide
    fzf
    zoxide
    direnv
    nix-direnv
    bat
    ripgrep
  ];
}
