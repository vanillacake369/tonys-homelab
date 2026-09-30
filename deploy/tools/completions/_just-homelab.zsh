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

_just_homelab_topology_all_names() {
  _just_homelab_topology_names hosts
  _just_homelab_topology_names vms
}

_just_homelab_k8s_names() {
  local root
  root="$(_just_homelab_root)"
  (cd "$root" && nix eval --impure --json --expr 'let inv = import ./ansible/inventory.nix {}; in inv.k8s_masters.hosts ++ inv.k8s_workers.hosts' 2>/dev/null | jq -r '.[]' 2>/dev/null)
}

_just_homelab_recipes() {
  local -a recipes
  recipes=(
    'check:run local guard checks'
    'gitops:manage Flux GitOps reconciliation'
    'host:manage physical hosts'
    'k8s:manage Kubernetes cluster lifecycle'
    'manifest:manage rendered manifests'
    'nix:manage Nix checks, updates, and GC'
    'setup:install local developer integrations'
    'vm:manage libvirt VMs'
  )
  _describe -t recipes 'just recipe' recipes
}

_just_homelab_platform_apps() {
  local root
  root="$(_just_homelab_root)"
  (cd "$root" && find deploy/platform/apps -maxdepth 1 -type f -name '*.cue' 2>/dev/null | sed 's#^.*/##; s#\.cue$##')
}

_just_homelab() {
  local -a check_targets gitops_actions host_actions hosts k8s_actions manifest_actions nix_actions setup_actions vm_actions vms

  _just_homelab_is_repo || return 1

  check_targets=(all generated nix k8s yaml shell actions secrets docs hooks recipes)
  host_actions=(
    'list:list declared physical hosts'
    'add:validate onboarding state for a host'
    'install:bootstrap a declared host with nixos-anywhere'
    'ssh:connect to a physical host'
    'plan:dry-activate a physical host'
    'apply:apply desired state to a physical host'
    'verify:verify runtime host health'
    'gc:run garbage collection on a physical host'
  )
  vm_actions=(
    'list:list declared VMs and reachability'
    'status:show VM reachability'
    'build:build VM base images on parent hosts'
    'provision:create or refresh VM runtime state'
    'ssh:connect to a VM through its parent host'
    'start:start VM systemd units'
    'stop:stop VM systemd units'
    'restart:restart VM systemd units'
    'plan:dry-activate a VM'
    'apply:apply desired state to a VM'
    'destroy:destroy VM runtime state'
    'check:check VM reachability'
    'verify:verify VM reachability'
    'gc:run garbage collection on a VM'
    'cleanup:remove stale libvirt domains'
    'sync:cleanup, build, then provision VMs'
  )
  k8s_actions=(
    'ssh:connect to the Kubernetes master'
    'bootstrap:run kubeadm bootstrap tasks'
    'verify:check cluster runtime health'
    'check:validate Kubernetes manifests locally'
    'deploy:bootstrap then verify the cluster'
    'clean:reset cluster state with confirmation'
    'reset:alias for clean'
    'reset-deploy:reset, bootstrap, then verify'
    'bootstrap-sops-age:install Flux SOPS age secret'
    'verify-sops-age:verify Flux SOPS age secret'
    'join:join one or all k8s nodes'
    'reconcile:check manifests, join, then verify'
  )
  gitops_actions=(
    'status:show Flux resource status'
    'plan:render generated manifests and run checks'
    'reconcile:force Flux source and kustomization reconcile'
    'bootstrap:bootstrap Flux against GitHub'
  )
  manifest_actions=(
    'render:render one generated app'
    'render-all:render all generated apps'
    'check:check one generated app'
    'check-all:check all generated apps'
    'check-generated:verify generated output is current'
    'diff:show generated manifest diff'
    'clean:remove generated manifests'
  )
  nix_actions=(
    'check:run Nix checks'
    'update:update flake inputs'
    'gc:run topology-scoped garbage collection'
  )
  setup_actions=(
    'hooks:install repository git hooks'
    'completions:install fish and zsh completions'
  )
  if (( CURRENT == 2 )); then
    _just_homelab_recipes
    return
  fi

  case "${words[2]}" in
    check)
      if (( CURRENT == 3 )); then
        compadd -- "${check_targets[@]}"
        return
      fi
    ;;
    host)
      if (( CURRENT == 3 )); then
        _describe -t actions 'host action' host_actions
        return
      fi

      case "${words[3]}" in
        add|install|ssh|plan|apply|verify|gc)
          hosts=(${(f)"$(_just_homelab_topology_names hosts)"})
          compadd -- "${hosts[@]}"
          return
          ;;
      esac
    ;;
    vm)
      if (( CURRENT == 3 )); then
        _describe -t actions 'vm action' vm_actions
        return
      fi

      case "${words[3]}" in
        list|status|build|provision|ssh|start|stop|restart|plan|apply|destroy|check|verify|gc|sync)
          vms=(${(f)"$(_just_homelab_topology_names vms)"})
          compadd -- "${vms[@]}"
          return
          ;;
      esac
    ;;
    k8s)
      if (( CURRENT == 3 )); then
        _describe -t actions 'k8s action' k8s_actions
        return
      fi

      case "${words[3]}" in
        join|reconcile)
          if (( CURRENT == 4 )); then
            compadd -- all ${(@f)"$(_just_homelab_k8s_names)"}
            return
          fi
          ;;
      esac
    ;;
    gitops)
      if (( CURRENT == 3 )); then
        _describe -t actions 'gitops action' gitops_actions
        return
      fi
    ;;
    manifest)
      if (( CURRENT == 3 )); then
        _describe -t actions 'manifest action' manifest_actions
        return
      fi
      case "${words[3]}" in
        render|check)
          if (( CURRENT == 4 )); then
            compadd -- ${(@f)"$(_just_homelab_platform_apps)"}
            return
          fi
          ;;
      esac
    ;;
    nix)
      if (( CURRENT == 3 )); then
        _describe -t actions 'nix action' nix_actions
        return
      fi

      if [[ "${words[3]}" == "gc" ]]; then
        if (( CURRENT == 4 )); then
          compadd -- all host-all vm-all host vm
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
    setup)
      if (( CURRENT == 3 )); then
        _describe -t actions 'setup action' setup_actions
        return
      fi
    ;;
  esac

  return 1
}
