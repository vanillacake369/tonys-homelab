#compdef just

source <(JUST_COMPLETE=zsh just 2>/dev/null)

_just_homelab_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

_just_homelab_is_repo() {
  local root
  root="$(_just_homelab_root)"
  [[ -f "$root/network/topology.nix" && -d "$root/deploy/platform/apps" && -f "$root/justfile" ]]
}

_just_homelab_topology_names() {
  local kind root
  kind="$1"
  root="$(_just_homelab_root)"
  (cd "$root" && nix eval --impure --json --expr "builtins.attrNames (import ./network/topology.nix).${kind}" 2>/dev/null | jq -r '.[]' 2>/dev/null)
}

_just_homelab_recipes() {
  local root
  root="$(_just_homelab_root)"
  (cd "$root" && just --summary 2>/dev/null)
}

_just_homelab_platform_apps() {
  local root
  root="$(_just_homelab_root)"
  (cd "$root" && find deploy/platform/apps -maxdepth 1 -type f -name '*.cue' 2>/dev/null | sed 's#^.*/##; s#\.cue$##')
}

_just_homelab() {
  local -a apps check_targets hosts infra_targets manifest_actions recipes vms

  if ! _just_homelab_is_repo; then
    if (( $+functions[_clap_dynamic_completer_just] )); then
      _clap_dynamic_completer_just "$@"
    fi
    return
  fi

  check_targets=(all nix k8s yaml shell actions secrets docs hooks recipes)
  infra_targets=(all host-all vm-all host vm)
  manifest_actions=(render render-all check check-all check-generated diff clean)

  if (( CURRENT == 2 )); then
    recipes=(${(z)"$(_just_homelab_recipes)"})
    compadd -- "${recipes[@]}"
    return
  fi

  case "${words[2]}" in
    apply|plan)
    if (( CURRENT == 3 )); then
      compadd -- gitops infra
      return
    fi

    if [[ "${words[3]}" == "infra" ]]; then
      if (( CURRENT == 4 )); then
        compadd -- "${infra_targets[@]}"
        return
      fi

      case "${words[4]}" in
        host)
          hosts=(${(f)"$(_just_homelab_topology_names hosts)"})
          compadd -- "${hosts[@]}"
          return
          ;;
        vm)
          vms=(${(f)"$(_just_homelab_topology_names vms)"})
          compadd -- "${vms[@]}"
          return
        ;;
      esac
    fi
    ;;
    check)
      if (( CURRENT == 3 )); then
        compadd -- "${check_targets[@]}"
        return
      fi
    ;;
    manifest)
      if (( CURRENT == 3 )); then
        compadd -- "${manifest_actions[@]}"
        return
      fi
      case "${words[3]}" in
        render|check)
          apps=(${(f)"$(_just_homelab_platform_apps)"})
          compadd -- "${apps[@]}"
          return
        ;;
      esac
    ;;
    bootstrap)
      if (( CURRENT == 3 )); then
        compadd -- gitops
        return
      fi
      if [[ "${words[3]}" == "gitops" && CURRENT == 4 ]]; then
        compadd -- flux
        return
      fi
    ;;
    status|reconcile)
      if (( CURRENT == 3 )); then
        compadd -- gitops
        return
      fi
    ;;
    gc)
      if (( CURRENT == 3 )); then
        compadd -- "${infra_targets[@]}"
        return
      fi

      case "${words[3]}" in
        host)
          hosts=(${(f)"$(_just_homelab_topology_names hosts)"})
          compadd -- "${hosts[@]}"
          return
          ;;
        vm)
          vms=(${(f)"$(_just_homelab_topology_names vms)"})
          compadd -- "${vms[@]}"
          return
        ;;
      esac
    ;;
  esac

  if (( $+functions[_clap_dynamic_completer_just] )); then
    _clap_dynamic_completer_just "$@"
  fi
}

compdef _just_homelab just
