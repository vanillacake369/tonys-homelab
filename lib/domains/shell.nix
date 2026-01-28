# Shell Domain
# Pure data: aliases, functions, zsh configuration
# No dependencies on other domains
{
  # Shell aliases (shared across NixOS and home-manager)
  aliases = {
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
  };

  # Shell functions (as strings, platform-agnostic)
  functions = {
    # Kubernetes manifest viewer with fzf
    kube-manifest = ''
      kube-manifest() {
        kubectl get $* -o name | \
            fzf --preview 'kubectl get {} -o yaml' \
                --bind "ctrl-r:reload(kubectl get $* -o name)" \
                --bind "ctrl-i:execute(kubectl edit {+})" \
                --header 'Ctrl-I: live edit | Ctrl-R: reload list';
      }
    '';

    # Git log with preview
    gitlog = ''
      gitlog() {
        (
          git log --oneline | fzf --preview 'git show --color=always {1}'
        )
      }
    '';

    # Process viewer
    pslog = ''
      pslog() {
        (
          ps axo pid,rss,comm --no-headers | fzf --preview 'ps o args {1}; ps mu {1}'
        )
      }
    '';

    # Search files by keyword with fzf
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

  # Linux-only functions
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

  # macOS-only functions
  functionsDarwin = {
    systemdlog = ''
      systemdlog() {
        (
          launchctl list | \
            fzf --preview 'launchctl print system/{1} 2>/dev/null || launchctl print user/$(id -u)/{1} 2>/dev/null || echo "Service details not available"' \
                --header 'Ctrl-I: edit plist | Ctrl-R: reload list | Ctrl-S: copy service info'
        )
      }
    '';
  };

  # ZSH specific configuration
  zsh = {
    ohMyZsh = {
      plugins = ["git" "kubectl" "kube-ps1"];
    };
    powerlevel10k = {
      enable = true;
    };
  };
}
