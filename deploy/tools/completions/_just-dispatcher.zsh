#compdef just

if command -v just >/dev/null 2>&1; then
  source <(JUST_COMPLETE=zsh just)
fi

_just_dispatch_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

_just_dispatch_source() {
  local helper="$1"
  local helper_path="${HOME}/.zfunc/${helper}"
  [[ -r "$helper_path" ]] && source "$helper_path"
}

_just_dispatch() {
  local root
  root="$(_just_dispatch_root)"

  if [[ -f "$root/network/topology.nix" && -d "$root/deploy/platform/apps" && -f "$root/justfile" ]]; then
    _just_dispatch_source _just_tonys_homelab
    if (( $+functions[_just_homelab] )); then
      _just_homelab "$@"
      return
    fi
  fi

  if [[ -f "$root/justfile" && -d "$root/mocks/java-mocks" && -d "$root/docs-wise" ]]; then
    _just_dispatch_source _just_tonys_interview
    if (( $+functions[_just_tonys_interview] )); then
      _just_tonys_interview "$@"
      return
    fi
  fi

  if (( $+functions[_clap_dynamic_completer_just] )); then
    _clap_dynamic_completer_just "$@"
  fi
}

_just() {
  _just_dispatch "$@"
}

compdef _just just
