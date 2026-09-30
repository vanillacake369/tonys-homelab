set shell := ["bash", "-euo", "pipefail", "-c"]

# NOTE :
# 네트워크 상태에 따라 ssh target 을
# lan ip 와 tailscale ip 중 동적으로 선택처리하도록
# ssh-config 생성시 topology.nix 와
# tailscale status 를 결합하여 처리
topology := "./network/topology.nix"

ssh-config := ```
  mkdir -p .cache
  config_file=".cache/ssh-config"

  # 데이터 가져오기
  nix_data=$(nix eval --impure --json --expr 'let t = import ./network/topology.nix; in { inherit (t) hosts vms dns vlans tailscale kubernetes storage; }')
  ts_data_raw=$(tailscale status --json 2>/dev/null || true)
  if echo "$ts_data_raw" | jq -e . >/dev/null 2>&1; then
    ts_data="$ts_data_raw"
  else
    ts_data='{"Peer":[]}'
  fi

  # Prefer a reachable LAN address. Fall back to an online Tailscale peer when
  # the host's SSH port is not reachable directly from the current network.
  reachable_lan_hosts='[]'
  if command -v nc >/dev/null 2>&1; then
    while IFS=$'\t' read -r host_name host_ip; do
      if nc -z -w 1 "$host_ip" 22 >/dev/null 2>&1; then
        reachable_lan_hosts=$(jq -c --arg host "$host_name" '. + [$host]' <<< "$reachable_lan_hosts")
      fi
    done < <(jq -r '.hosts | to_entries[] | [.key, .value.uplink.ip] | @tsv' <<< "$nix_data")
  fi

  # 물리 호스트 및 VM 설정 생성
  echo "$nix_data" | jq -r --argjson ts "$ts_data" --argjson reachableLan "$reachable_lan_hosts" '
    (.hosts | to_entries[] as $host |
      (if ($reachableLan | index($host.key)) != null then
        $host.value.uplink.ip
      else
        (($ts.Peer[]? | select(.Online == true and (.HostName == $host.key or (.DNSName | startswith($host.key+".")))) | .TailscaleIPs[0]) // $host.value.uplink.ip)
      end) as $ip |
      "Host \($host.key)\n    HostName \($ip)\n    User \($host.value.user)\n    StrictHostKeyChecking no\n"),
    (.vms | to_entries[] as $vm |
      "Host \($vm.key) \($vm.value.ip)\n    HostName \($vm.value.ip)\n    User root\n    ProxyJump \($vm.value.parentHost)\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n")
  ' > "$config_file"

  echo "$config_file"
```

# Run local guard checks. Targets: all, generated, nix, k8s, yaml, shell, actions, secrets, docs, hooks, recipes.
check target="all" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        echo "Stubbed check: {{ target }} {{ args }}"
        exit 0
    fi
    if [ -z "${HOMELAB_IN_NIX_DEVELOP:-}" ] && [ -z "${IN_NIX_SHELL:-}" ]; then
        exec env HOMELAB_IN_NIX_DEVELOP=1 nix develop -c just check "{{ target }}" {{ args }}
    fi

    case "{{ target }}" in
        all)
            for item in generated nix k8s yaml shell actions secrets docs hooks recipes; do
                printf '\n==> just check %s\n' "$item"
                just check "$item"
            done
            printf '\nAll local CI checks passed.\n'
            ;;
        generated) just _check_generated ;;
        nix) just _check_nix ;;
        k8s) just _check_k8s ;;
        yaml) just _check_yaml ;;
        shell) just _check_shell ;;
        actions) just _check_actions ;;
        secrets) just _check_secrets ;;
        docs) just _check_docs ;;
        hooks) just _check_hooks ;;
        recipes) just _check_recipe_contracts ;;
        *)
            echo "Unknown check target: {{ target }}" >&2
            echo "Expected one of: all, generated, nix, k8s, yaml, shell, actions, secrets, docs, hooks, recipes" >&2
            exit 2
            ;;
    esac

# Manage physical hosts. Actions: list, add, install, ssh, plan, apply, verify, gc.
host action="list" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        list) just _host_list {{ args }} ;;
        add) just _host_add {{ args }} ;;
        install) just _host_install {{ args }} ;;
        ssh) just _host_ssh {{ args }} ;;
        plan) just _host_plan {{ args }} ;;
        apply) just _host_apply {{ args }} ;;
        verify) just _host_verify {{ args }} ;;
        gc) just _host_gc {{ args }} ;;
        *)
            echo "Unknown host action: {{ action }}" >&2
            echo "Expected one of: list, add, install, ssh, plan, apply, verify, gc" >&2
            exit 2
            ;;
    esac

# Manage VMs. Actions: list, status, build, provision, ssh, start, stop, restart, plan, apply, destroy, check, verify, gc, cleanup, sync.
vm action="status" *names:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        list|status) just _vm_status {{ names }} ;;
        ssh) just _vm_ssh {{ names }} ;;
        start) just _vm_systemctl start {{ names }} ;;
        stop) just _vm_systemctl stop {{ names }} ;;
        restart) just _vm_systemctl restart {{ names }} ;;
        build) just _vm_build {{ names }} ;;
        provision) just _vm_provision {{ names }} ;;
        plan) just _vm_plan {{ names }} ;;
        apply) just _vm_apply {{ names }} ;;
        check|verify) just _vm_status {{ names }} ;;
        gc) just _gc vm {{ names }} ;;
        destroy) just _vm_destroy {{ names }} ;;
        cleanup) just _vm_cleanup ;;
        sync) just _vm_cleanup && just _vm_build {{ names }} && just _vm_provision {{ names }} ;;
        *)
            echo "Unknown VM action: {{ action }}" >&2
            echo "Expected one of: list, status, build, provision, ssh, start, stop, restart, plan, apply, destroy, check, verify, gc, cleanup, sync" >&2
            exit 2
            ;;
    esac

# Manage Kubernetes cluster lifecycle. Actions: ssh, bootstrap, verify, check, deploy, clean, reset, reset-deploy, bootstrap-sops-age, verify-sops-age, join <node|all>, reconcile <node|all>.
k8s action="verify" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        ssh) just _k8s_ssh ;;
        verify) just _k8s_verify ;;
        check) just check k8s ;;
        bootstrap) just _k8s_bootstrap ;;
        deploy) just _k8s_bootstrap && just _k8s_verify ;;
        clean|reset) just _k8s_clean ;;
        reset-deploy) just _k8s_clean && just _k8s_bootstrap && just _k8s_verify ;;
        bootstrap-sops-age) just _k8s_bootstrap_sops_age ;;
        verify-sops-age) just _k8s_verify_sops_age ;;
        join) just _k8s_join {{ args }} ;;
        reconcile) just _k8s_reconcile {{ args }} ;;
        *)
            echo "Unknown Kubernetes action: {{ action }}" >&2
            echo "Expected one of: ssh, bootstrap, verify, check, deploy, clean, reset, reset-deploy, bootstrap-sops-age, verify-sops-age, join, reconcile" >&2
            exit 2
            ;;
    esac

# Manage GitOps reconciliation. Actions: status, plan, reconcile, bootstrap.
gitops action="status" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        status)
            if [ -n "{{ args }}" ]; then
                echo "Usage: just gitops status" >&2
                exit 2
            fi
            just _gitops_status
            ;;
        plan)
            if [ -n "{{ args }}" ]; then
                echo "Usage: just gitops plan" >&2
                exit 2
            fi
            just _gitops_plan
            echo "Plan OK. To reconcile via Flux: CONFIRM_DEPLOY=homelab just gitops reconcile"
            ;;
        reconcile|apply)
            if [ -n "{{ args }}" ]; then
                echo "Usage: CONFIRM_DEPLOY=homelab just gitops reconcile" >&2
                exit 2
            fi
            just _require_confirm_deploy "just gitops reconcile"
            just gitops plan
            just _require_gitops_tree_clean
            just _gitops_reconcile
            ;;
        bootstrap) just _flux_bootstrap {{ args }} ;;
        *)
            echo "Unknown GitOps action: {{ action }}" >&2
            echo "Expected one of: status, plan, reconcile, bootstrap" >&2
            exit 2
            ;;
    esac

# Manage rendered manifests. Actions: render, render-all, check, check-all, check-generated, diff, clean.
manifest action="render" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _manifest "{{ action }}" {{ args }}

# Strangler namespace for Nix operations. Actions: check, update, gc.
nix action="check" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        check)
            if [ -n "{{ args }}" ]; then
                echo "Usage: just nix check" >&2
                exit 2
            fi
            just check nix
            ;;
        update)
            if [ -n "{{ args }}" ]; then
                echo "Usage: just nix update" >&2
                exit 2
            fi
            just _update
            ;;
        gc)
            just _gc {{ args }}
            ;;
        *)
            echo "Unknown Nix action: {{ action }}" >&2
            echo "Expected one of: check, update, gc" >&2
            exit 2
            ;;
    esac

# Strangler namespace for local setup operations. Actions: hooks, completions.
setup action *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ args }}" ]; then
        echo "Target 'setup {{ action }}' does not accept extra arguments: {{ args }}" >&2
        exit 2
    fi
    case "{{ action }}" in
        hooks) just _install_hooks ;;
        completions) just _install_completions ;;
        *)
            echo "Unknown setup action: {{ action }}" >&2
            echo "Expected one of: hooks, completions" >&2
            exit 2
            ;;
    esac

[private]
_plan target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            if [ -n "{{ args }}" ]; then
                echo "Target 'gitops' does not accept extra arguments: {{ args }}" >&2
                exit 2
            fi
            just _gitops_plan
            echo "Plan OK. To reconcile via Flux: CONFIRM_DEPLOY=homelab just gitops reconcile"
            ;;
        infra)
            just _infra_plan {{ args }}
            ;;
        all|host-all|hosts|vm-all|vms|host|vm|node|nodes)
            just _infra_plan "{{ target }}" {{ args }}
            ;;
        *)
            just _infra_plan "{{ target }}" {{ args }}
            ;;
    esac

[private]
_apply target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            if [ -n "{{ args }}" ]; then
                echo "Target 'gitops' does not accept extra arguments: {{ args }}" >&2
                exit 2
            fi
            just _require_confirm_deploy "just gitops reconcile"
            just _plan gitops
            just _require_gitops_tree_clean
            just _gitops_reconcile
            ;;
        infra)
            just _topology_targets {{ args }} >/dev/null
            just _require_confirm_deploy "just host/vm apply"
            just _plan infra {{ args }}
            just _deploy_resolved {{ args }}
            ;;
        all|host-all|hosts|vm-all|vms|host|vm|node|nodes)
            just _topology_targets "{{ target }}" {{ args }} >/dev/null
            just _require_confirm_deploy "just host/vm apply"
            just _plan infra "{{ target }}" {{ args }}
            just _deploy_resolved "{{ target }}" {{ args }}
            ;;
        *)
            just _topology_targets "{{ target }}" {{ args }} >/dev/null
            just _require_confirm_deploy "just host/vm apply"
            just _plan infra "{{ target }}" {{ args }}
            just _deploy_resolved "{{ target }}" {{ args }}
            ;;
    esac

[private]
_manifest action="render" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    split_args() {
        if [ -n "{{ args }}" ]; then
            read -r -a args_array <<< "{{ args }}"
        else
            args_array=()
        fi
    }

    set_app_arg() {
        if [ "${#args_array[@]}" -gt 1 ]; then
            echo "Usage: just _manifest {{ action }} [app]" >&2
            exit 2
        fi
        if [ "${#args_array[@]}" -eq 1 ]; then
            platform_app="${args_array[0]}"
        else
            platform_app="${APP:-tonys-gis}"
        fi
    }

    require_no_args() {
        if [ "${#args_array[@]}" -ne 0 ]; then
            echo "Target '{{ action }}' does not accept app names: ${args_array[*]}" >&2
            exit 2
        fi
    }

    split_args

    case "{{ action }}" in
        render)
            set_app_arg
            ./deploy/tools/platform-render.sh render "$platform_app"
            ;;
        render-all) require_no_args; ./deploy/tools/platform-render.sh render-all ;;
        check)
            set_app_arg
            ./deploy/tools/platform-render.sh check "$platform_app"
            ;;
        check-all) require_no_args; ./deploy/tools/platform-render.sh check-all ;;
        check-generated) require_no_args; ./deploy/tools/platform-render.sh check-generated ;;
        diff|diff-generated) require_no_args; ./deploy/tools/platform-render.sh diff-generated ;;
        clean|clean-generated) require_no_args; ./deploy/tools/platform-render.sh clean-generated ;;
        *)
            echo "Unknown manifest action: {{ action }}" >&2
            echo "Expected one of: render, render-all, check, check-all, check-generated, diff, clean" >&2
            exit 2
            ;;
    esac

[private]
_ssh_connect node:
    ssh -F {{ ssh-config }} {{ node }}

[private]
_gc target="all" *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _topology_targets "{{ target }}" {{ nodes }})"
    if [ "$targets" = "__all__" ]; then
        targets="$(nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)' | jq -r 'join(",")')"
    fi

    IFS=, read -r -a target_array <<< "$targets"
    for node in "${target_array[@]}"; do
        if [ -z "$node" ]; then
            continue
        fi
        echo "=== GC: $node ==="
        just _ssh "$node" "sudo nix-collect-garbage -d && sudo nix-store --optimize && sudo journalctl --vacuum-time=1d" || echo "Failed"
    done

# Update flake inputs.
[private]
_update:
    nix flake update

# Install repository-managed git hooks locally.
[private]
_install_hooks:
    git config core.hooksPath .githooks
    echo "Installed git hooks: .githooks"

# Install shell completions for topology-aware homelab just commands.
[private]
_install_completions:
    #!/usr/bin/env bash
    set -euo pipefail
    install_completion() {
        local src="$1" dest="$2"
        mkdir -p "$(dirname "$dest")"
        if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
            cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
        fi
        cp "$src" "$dest"
    }

    mkdir -p "$HOME/.config/fish/completions" "$HOME/.config/fish/conf.d" "$HOME/.zfunc"
    install_completion deploy/tools/completions/just-completion-path.fish "$HOME/.config/fish/conf.d/just-completion-path.fish"
    install_completion deploy/tools/completions/just-dispatcher.fish "$HOME/.config/fish/completions/just.fish"
    install_completion deploy/tools/completions/just-homelab.fish "$HOME/.config/fish/completions/just-tonys-homelab.fish"
    install_completion deploy/tools/completions/_just-dispatcher.zsh "$HOME/.zfunc/_just"
    install_completion deploy/tools/completions/_just-homelab.zsh "$HOME/.zfunc/_just_tonys_homelab"
    echo "Installed fish path config: $HOME/.config/fish/conf.d/just-completion-path.fish"
    echo "Installed fish dispatcher:  $HOME/.config/fish/completions/just.fish"
    echo "Installed fish helper:     $HOME/.config/fish/completions/just-tonys-homelab.fish"
    echo "Installed zsh dispatcher:  $HOME/.zfunc/_just"
    echo "Installed zsh helper:      $HOME/.zfunc/_just_tonys_homelab"
    echo "Existing completion files are backed up automatically before overwrite."
    echo "The homelab-specific completion activates only inside this repository."
    echo 'For zsh, ensure this is in ~/.zshrc before compinit: fpath=("$HOME/.zfunc" $fpath)'

[private]
_colmena +args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'colmena %s\n' "{{ args }}" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    SSH_CONFIG_FILE={{ ssh-config }} nix run --impure .#colmena -- {{ args }}

[private]
_require_confirm_deploy command:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${CONFIRM_DEPLOY:-}" != "homelab" ]; then
        echo "Refusing remote mutation without explicit confirmation." >&2
        echo "Run: CONFIRM_DEPLOY=homelab {{ command }}" >&2
        exit 2
    fi

[private]
_gitops_plan:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Target: gitops"
    echo "Action: render generated manifests, show generated diff, and run local checks."
    just _manifest diff
    just check

[private]
_require_gitops_tree_clean:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'gitops tree clean\n' >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    dirty="$(
        git status --porcelain -- \
            deploy/platform/api \
            deploy/platform/apps \
            deploy/platform/policies \
            deploy/platform/profiles \
            deploy/platform/render \
            deploy/k8s/generated \
            deploy/k8s/clusters/homelab \
            deploy/k8s/infrastructure \
            deploy/k8s/apps
    )"
    if [ -n "$dirty" ]; then
        echo "Refusing GitOps reconcile with uncommitted GitOps changes." >&2
        echo "Flux consumes Git state, not local working tree changes." >&2
        echo "$dirty" >&2
        exit 2
    fi

[private]
_gitops_status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "GitOps provider: flux"
    just _flux_status

[private]
_gitops_reconcile:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "GitOps provider: flux"
    echo "Action: reconcile"
    just _flux_reconcile

[private]
_topology_names kind:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ kind }}" in
        hosts|vms)
            nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).{{ kind }}' | jq -r '.[]'
            ;;
        *)
            echo "Unknown topology kind: {{ kind }}" >&2
            echo "Expected one of: hosts, vms" >&2
            exit 2
            ;;
    esac

[private]
_topology_targets target="all" *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    split_nodes() {
        if [ -n "{{ nodes }}" ]; then
            read -r -a nodes_array <<< "{{ nodes }}"
        else
            nodes_array=()
        fi
    }

    join_kind() {
        local kind="$1"
        nix eval --impure --json --expr "builtins.attrNames (import {{ topology }}).${kind}" | jq -r 'join(",")'
    }

    assert_no_nodes() {
        if [ "${#nodes_array[@]}" -ne 0 ]; then
            echo "Target '{{ target }}' does not accept node names: ${nodes_array[*]}" >&2
            exit 2
        fi
    }

    assert_some_nodes() {
        local usage="$1"
        if [ "${#nodes_array[@]}" -eq 0 ]; then
            echo "Usage: $usage" >&2
            exit 2
        fi
    }

    assert_known() {
        local kind="$1"
        shift
        local allowed_json
        allowed_json="$(nix eval --impure --json --expr "builtins.attrNames (import {{ topology }}).${kind}")"

        for node in "$@"; do
            if ! jq -e --arg node "$node" 'index($node) != null' <<< "$allowed_json" >/dev/null; then
                echo "Unknown ${kind%?}: $node" >&2
                echo "Known ${kind}: $(jq -r 'join(", ")' <<< "$allowed_json")" >&2
                exit 2
            fi
        done
    }

    join_nodes() {
        local IFS=,
        echo "$*"
    }

    split_nodes

    case "{{ target }}" in
        all)
            assert_no_nodes
            echo "__all__"
            ;;
        host-all|hosts)
            assert_no_nodes
            join_kind hosts
            ;;
        vm-all|vms)
            assert_no_nodes
            join_kind vms
            ;;
        host)
            assert_some_nodes "<recipe> host <host> [host...]"
            assert_known hosts "${nodes_array[@]}"
            join_nodes "${nodes_array[@]}"
            ;;
        vm)
            assert_some_nodes "<recipe> vm <vm> [vm...]"
            assert_known vms "${nodes_array[@]}"
            join_nodes "${nodes_array[@]}"
            ;;
        node|nodes)
            assert_some_nodes "<recipe> node <node> [node...]"
            all_json="$(nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)')"
            for node in "${nodes_array[@]}"; do
                if ! jq -e --arg node "$node" 'index($node) != null' <<< "$all_json" >/dev/null; then
                    echo "Unknown node: $node" >&2
                    echo "Known nodes: $(jq -r 'join(", ")' <<< "$all_json")" >&2
                    exit 2
                fi
            done
            echo "Deprecated: use '<recipe> host <name>' or '<recipe> vm <name>' instead of '<recipe> node <name>'." >&2
            join_nodes "${nodes_array[@]}"
            ;;
        *)
            nodes_array=("{{ target }}")
            if [ -n "{{ nodes }}" ]; then
                read -r -a extra_nodes <<< "{{ nodes }}"
                nodes_array+=("${extra_nodes[@]}")
            fi
            all_json="$(nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)')"
            for node in "${nodes_array[@]}"; do
                if ! jq -e --arg node "$node" 'index($node) != null' <<< "$all_json" >/dev/null; then
                    echo "Unknown topology target: {{ target }}" >&2
                    echo "Expected one of: all, host-all, vm-all, host, vm" >&2
                    echo "Known legacy node names: $(jq -r 'join(", ")' <<< "$all_json")" >&2
                    exit 2
                fi
            done
            echo "Deprecated: use '<recipe> host <name>' or '<recipe> vm <name>' instead of implicit node names." >&2
            join_nodes "${nodes_array[@]}"
            ;;
    esac

[private]
_infra_plan target="all" *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    just _topology_targets "{{ target }}" {{ nodes }} >/dev/null
    just check
    case "{{ target }}" in
        all)
            just _deploy_host_plan
            just _deploy_vm_plan
            ;;
        host-all|hosts)
            just _deploy_host_plan
            ;;
        vm-all|vms)
            just _deploy_vm_plan
            ;;
        host|vm|node|nodes)
            just _deploy_resolved_plan "{{ target }}" {{ nodes }}
            ;;
        *)
            just _deploy_resolved_plan "{{ target }}" {{ nodes }}
            ;;
    esac

[private]
_deploy_targets target="all" *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    just _topology_targets "{{ target }}" {{ nodes }}

[private]
_host_list *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ args }}" ]; then
        echo "Usage: just host list" >&2
        exit 2
    fi
    just _topology_names hosts

[private]
_host_add name target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{ name }}"
    target="{{ target }}"
    if [ -n "{{ args }}" ]; then
        echo "Usage: just host add <declared-hostname> <ssh-target>" >&2
        echo "Example: just host add homelab-2 root@192.168.45.173" >&2
        exit 2
    fi
    just _topology_targets host "$name" >/dev/null
    if [ ! -f "nodes/physical/${name}.nix" ]; then
        echo "Missing physical node config: nodes/physical/${name}.nix" >&2
        exit 2
    fi
    if [ ! -f "nodes/physical/disko-config-${name}.nix" ]; then
        echo "Missing Disko config: nodes/physical/disko-config-${name}.nix" >&2
        exit 2
    fi

    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'host add %s %s\n' "$name" "$target" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi

    ssh_remote() {
        if [ -n "${SSHPASS:-}" ]; then
            sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$target" "$@"
        else
            ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$target" "$@"
        fi
    }

    echo "==> SSH connectivity: $target"
    ssh_remote 'hostname; ip -br addr; test -r /etc/ssh/ssh_host_ed25519_key.pub'

    echo "==> SSH host identity age recipient"
    host_pub="$(ssh_remote 'cat /etc/ssh/ssh_host_ed25519_key.pub')"
    recipient="$(printf '%s\n' "$host_pub" | ssh-to-age)"
    if ! grep -Fq "$recipient" .sops.yaml; then
        echo "Missing .sops.yaml recipient for $name: $recipient" >&2
        echo "Add it under keys and the secrets/* key_groups, then run: sops updatekeys secrets/secrets.yaml" >&2
        exit 2
    fi

    echo "==> Static repository validation"
    just check docs
    nix eval --impure --json ".#nixosConfigurations.${name}.config.node" >/dev/null
    nix eval --impure --raw --expr "(import ./nodes/physical/disko-config-${name}.nix {}).disko.devices.disk.main.device" >/dev/null

    if command -v sops >/dev/null 2>&1; then
        echo "==> Updating SOPS recipients for secrets/secrets.yaml"
        sops updatekeys -y secrets/secrets.yaml
    else
        echo "WARN: sops is not available; skipped: sops updatekeys -y secrets/secrets.yaml" >&2
    fi

    echo "host add OK: $name is declared and the target host identity is represented in .sops.yaml"

[private]
_host_install name *args:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{ name }}"
    if [ -n "{{ args }}" ]; then
        echo "Usage: CONFIRM_INSTALL='<host>:/dev/...' just host install <host>" >&2
        echo "Optional: HOST_INSTALL_TARGET=root@installer-ip SSHPASS='temporary-password'" >&2
        exit 2
    fi
    just _topology_targets host "$name" >/dev/null
    if [ ! -f "nodes/physical/disko-config-${name}.nix" ]; then
        echo "Missing Disko config: nodes/physical/disko-config-${name}.nix" >&2
        exit 2
    fi

    disk="$(nix eval --impure --raw --expr "(import ./nodes/physical/disko-config-${name}.nix {}).disko.devices.disk.main.device")"
    expected_confirm="${name}:${disk}"
    if [ "${CONFIRM_INSTALL:-}" != "$expected_confirm" ]; then
        echo "Refusing destructive host install." >&2
        echo "This will erase: $disk" >&2
        echo "Run with: CONFIRM_INSTALL='$expected_confirm' just host install $name" >&2
        echo "Optional installer target override: HOST_INSTALL_TARGET=root@<ip>" >&2
        exit 2
    fi

    target="${HOST_INSTALL_TARGET:-}"
    if [ -z "$target" ]; then
        host_ip="$(nix eval --impure --raw --expr "(import {{ topology }}).hosts.\"${name}\".uplink.ip")"
        target="root@${host_ip}"
    fi

    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'nixos-anywhere %s %s %s\n' "$name" "$target" "$disk" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi

    echo "==> Install preflight"
    nix eval --impure --json ".#nixosConfigurations.${name}.config.system.build.toplevel.drvPath" >/dev/null
    if [ -n "${SSHPASS:-}" ]; then
        sshpass -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$target" "test -b '$disk' && cat /sys/firmware/efi/fw_platform_size 2>/dev/null || true"
    else
        ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$target" "test -b '$disk' && cat /sys/firmware/efi/fw_platform_size 2>/dev/null || true"
    fi

    echo "Node:        $name"
    echo "Target:      $target"
    echo "Install disk:$disk"
    echo "Flake:       .#$name"
    echo
    echo "==> Running nixos-anywhere"
    env nix run github:nix-community/nixos-anywhere -- \
        --print-build-logs \
        --env-password \
        --copy-host-keys \
        --build-on-remote \
        --flake ".#${name}" \
        --target-host "$target" \
        --ssh-option StrictHostKeyChecking=no

[private]
_host_ssh name:
    #!/usr/bin/env bash
    set -euo pipefail
    just _topology_targets host "{{ name }}" >/dev/null
    exec just _ssh_connect "{{ name }}"

[private]
_host_plan name:
    #!/usr/bin/env bash
    set -euo pipefail
    exec just _infra_plan host "{{ name }}"

[private]
_host_apply name:
    #!/usr/bin/env bash
    set -euo pipefail
    just _topology_targets host "{{ name }}" >/dev/null
    just _require_confirm_deploy "just host apply {{ name }}"
    just _infra_plan host "{{ name }}"
    just _deploy_resolved host "{{ name }}"

[private]
_host_gc name:
    #!/usr/bin/env bash
    set -euo pipefail
    exec just _gc host "{{ name }}"

[private]
_host_verify name:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{ name }}"
    just _topology_targets host "$name" >/dev/null

    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'host verify %s\n' "$name" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi

    host_json="$(
        nix eval --impure --json --expr "(import {{ topology }}).hosts.\"$name\""
    )"
    expected_ip="$(jq -r '.uplink.ip' <<< "$host_json")"
    expected_prefix="$(jq -r '.uplink.prefixLength' <<< "$host_json")"
    expected_if="$(jq -r '.uplink.interface' <<< "$host_json")"
    expected_gateway="$(jq -r '.uplink.gateway' <<< "$host_json")"
    expected_user="$(jq -r '.user' <<< "$host_json")"
    node_role="$(nix eval --impure --raw ".#nixosConfigurations.${name}.config.node.role")"
    expected_domains="$(nix eval --impure --json --expr "let t = import {{ topology }}; p = import ./network/projections.nix { topology = t; }; in builtins.attrNames (p.vmsForHost \"$name\")" | jq -r 'join(" ")')"
    has_vlans="$(jq -r 'has("vlans")' <<< "$host_json")"
    bridge_if="vmbr0"
    mgmt_if=""
    svc_if=""
    mgmt_cidr=""
    svc_cidr=""
    if [ "$has_vlans" = "true" ]; then
        mgmt_vlan_id="$(nix eval --impure --raw --expr 'toString (import {{ topology }}).vlans.management.id')"
        svc_vlan_id="$(nix eval --impure --raw --expr 'toString (import {{ topology }}).vlans.services.id')"
        mgmt_prefix="$(nix eval --impure --raw --expr 'toString (import {{ topology }}).vlans.management.prefixLength')"
        svc_prefix="$(nix eval --impure --raw --expr 'toString (import {{ topology }}).vlans.services.prefixLength')"
        mgmt_if="vlan${mgmt_vlan_id}"
        svc_if="vlan${svc_vlan_id}"
        mgmt_cidr="$(jq -r '.vlans.management.address' <<< "$host_json")/${mgmt_prefix}"
        svc_cidr="$(jq -r '.vlans.services.address' <<< "$host_json")/${svc_prefix}"
    fi

    remote_script="$(mktemp)"
    trap 'rm -f "$remote_script"' EXIT
    cat > "$remote_script" <<'REMOTE'
    set -euo pipefail
    expected_name="$1"
    expected_ip="$2"
    expected_prefix="$3"
    expected_if="$4"
    expected_gateway="$5"
    expected_user="$6"
    node_role="$7"
    has_vlans="$8"
    bridge_if="$9"
    mgmt_if="${10}"
    svc_if="${11}"
    mgmt_cidr="${12}"
    svc_cidr="${13}"
    expected_domains="${14}"

    check() {
        printf 'ok: %s\n' "$*"
    }

    require_active() {
        local unit="$1"
        systemctl is-active --quiet "$unit"
        check "$unit active"
    }

    require_unit_exists() {
        local unit="$1"
        systemctl cat "$unit" >/dev/null
        check "$unit unit exists"
    }

    require_ipv4() {
        local iface="$1" cidr="$2"
        if ! ip -4 -o addr show dev "$iface" | awk '{print $4}' | grep -qx "$cidr"; then
            echo "missing expected address $cidr on $iface" >&2
            ip -br addr show dev "$iface" >&2 || true
            exit 1
        fi
        check "$iface has $cidr"
    }

    actual_name="$(hostname)"
    if [ "$actual_name" != "$expected_name" ]; then
        echo "hostname mismatch: expected $expected_name, got $actual_name" >&2
        exit 1
    fi
    check "hostname $expected_name"

    current_system="$(readlink -f /run/current-system)"
    case "$current_system" in
        /nix/store/*-nixos-system-*) ;;
        *)
            echo "unexpected current system: $current_system" >&2
            exit 1
            ;;
    esac
    check "current system $current_system"

    require_active sshd
    require_active systemd-networkd
    require_active systemd-resolved

    ip link show dev "$expected_if" >/dev/null
    check "uplink interface $expected_if exists"

    address_if="$expected_if"
    if [ "$has_vlans" = "true" ]; then
        address_if="$bridge_if"
        ip link show dev "$bridge_if" >/dev/null
        ip link show dev "$mgmt_if" >/dev/null
        ip link show dev "$svc_if" >/dev/null
        master="$(basename "$(readlink -f "/sys/class/net/${expected_if}/master")")"
        if [ "$master" != "$bridge_if" ]; then
            echo "uplink $expected_if is not enslaved to $bridge_if" >&2
            exit 1
        fi
        check "$expected_if enslaved to $bridge_if"
        if [ "$(cat "/sys/class/net/${bridge_if}/bridge/vlan_filtering")" != "1" ]; then
            echo "$bridge_if does not have VLAN filtering enabled" >&2
            exit 1
        fi
        check "$bridge_if VLAN filtering enabled"
        require_ipv4 "$mgmt_if" "$mgmt_cidr"
        require_ipv4 "$svc_if" "$svc_cidr"
        [ "$(sysctl -n net.ipv4.ip_forward)" = "1" ]
        check "IPv4 forwarding enabled"
    fi
    require_ipv4 "$address_if" "${expected_ip}/${expected_prefix}"

    if ! ip route show default | grep -q "via ${expected_gateway}"; then
        echo "missing default route via $expected_gateway" >&2
        ip route show default >&2 || true
        exit 1
    fi
    check "default route via $expected_gateway"

    for user in root "$expected_user"; do
        getent passwd "$user" >/dev/null
        hash="$(sudo -n getent shadow "$user" | cut -d: -f2 || true)"
        case "$hash" in
            ''|'!'|'*')
                echo "user $user has no usable password hash" >&2
                exit 1
                ;;
        esac
        check "$user password hash present"
    done

    test -e /run/secrets-for-users/users/rootPassword
    test -e "/run/secrets-for-users/users/${expected_user}Password"
    check "sops user password files exist"

    if [ "$node_role" = "host" ]; then
        if systemctl is-active --quiet libvirtd; then
            check "libvirtd active"
        elif systemctl is-active --quiet virtqemud; then
            check "virtqemud active"
        else
            echo "neither libvirtd nor virtqemud is active" >&2
            exit 1
        fi
        sudo -n virsh list --all >/dev/null
        check "virsh can list domains"
        for domain in $expected_domains; do
            sudo -n virsh dominfo "$domain" >/dev/null
            check "libvirt domain $domain defined"
        done
        test -e /run/secrets/tailscale/clientSecret
        check "tailscale client secret exists"
        require_active tailscaled
        if command -v tailscale >/dev/null; then
            tailscale status >/dev/null
            check "tailscale status available"
        fi
    fi

    if [ "$node_role" = "k8s-worker" ]; then
        require_active containerd
        test -S /run/containerd/containerd.sock
        check "containerd socket exists"
        require_unit_exists kubelet
        test -d /var/lib/kubelet
        check "kubelet state directory exists"
    fi

    echo "host verify OK: $expected_name"
    ip -br addr show dev "$expected_if"
    if [ "$has_vlans" = "true" ]; then
        ip -br addr show dev "$bridge_if"
        ip -br addr show dev "$mgmt_if"
        ip -br addr show dev "$svc_if"
    fi
    REMOTE

    ssh -F {{ ssh-config }} "$name" "bash -s -- '$name' '$expected_ip' '$expected_prefix' '$expected_if' '$expected_gateway' '$expected_user' '$node_role' '$has_vlans' '$bridge_if' '$mgmt_if' '$svc_if' '$mgmt_cidr' '$svc_cidr' '$expected_domains'" < "$remote_script"

[private]
_deploy_resolved target="all" *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _topology_targets "{{ target }}" {{ nodes }})"
    if [ "$targets" = "__all__" ]; then
        just _deploy_host
        just _deploy_vm
    else
        just _colmena apply --on "$targets" --verbose
    fi

[private]
_deploy_resolved_plan target *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _topology_targets "{{ target }}" {{ nodes }})"
    if [ "$targets" = "__all__" ]; then
        just _deploy_host_plan
        just _deploy_vm_plan
    else
        echo "Target: nodes ($targets)"
        just _colmena apply dry-activate --no-keys --on "$targets" --verbose
    fi

[private]
_ssh node +cmd:
    ssh -n -F {{ ssh-config }} {{ node }} '{{ cmd }}'

[private]
_ansible +args:
    ANSIBLE_LOCAL_TEMP="/tmp/ansible-local" TMPDIR="/tmp" ANSIBLE_SSH_ARGS="-F {{ ssh-config }}" ansible-playbook -i ansible/inventory.py {{ args }}

[private]
_master_ip:
    nix eval --impure --json --expr '(import {{ topology }}).vms' | jq -r 'to_entries[] | select(.key | startswith("k8s-master")) | .value.ip' | head -1

[private]
_check_nix:
    #!/usr/bin/env bash
    set -euo pipefail

    run() {
        printf '\n==> %s\n' "$*"
        "$@"
    }

    run deadnix --fail
    printf '\n==> statix check (informational)\n'
    statix check --format errfmt 2>&1 | sed -n '1,80p' || true
    run alejandra --check .
    run nix flake check --impure --no-build

[private]
_check_generated:
    just _manifest check-generated

[private]
_check_k8s:
    #!/usr/bin/env bash
    set -euo pipefail

    roots=(
        deploy/k8s/clusters/homelab
        deploy/k8s/infrastructure
        deploy/k8s/apps/bookorbit
        deploy/k8s/generated/apps
    )

    run() {
        printf '\n==> %s\n' "$*"
        "$@"
    }

    sanitize_sops_metadata() {
        awk '
            /^---[[:space:]]*$/ { skip = 0; print; next }
            skip && /^[^[:space:]#][^:]*:/ { skip = 0 }
            /^sops:[[:space:]]*$/ { skip = 1; next }
            !skip { print }
        ' "$1" > "$2"
    }

    require_default_deny() {
        local namespace="$1" rendered="$2" namespace_count count
        namespace_count="$(
            ns="$namespace" yq ea '[select(.kind == "Namespace" and .metadata.name == strenv(ns))] | length' "$rendered"
        )"
        if [ "$namespace_count" -eq 0 ]; then
            return 0
        fi
        count="$(
            ns="$namespace" yq ea '[select(.kind == "CiliumNetworkPolicy" and .metadata.namespace == strenv(ns) and (.spec.endpointSelector | length) == 0 and ((.spec.ingress // []) | length) == 0 and ((.spec.egress // []) | length) == 0)] | length' "$rendered"
        )"
        if [ "$count" -lt 1 ]; then
            echo "Missing namespace-wide default-deny CiliumNetworkPolicy in namespace: $namespace" >&2
            exit 1
        fi
    }

    require_flux_root() {
        local rendered="$1" missing=0
        if ! yq ea 'select(.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "flux-system") | .metadata.name' "$rendered" | grep -qx flux-system; then
            return 0
        fi
        for name in infrastructure apps bookorbit generated-apps; do
            if ! name="$name" yq ea 'select(.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == strenv(name)) | .metadata.name' "$rendered" | grep -qx "$name"; then
                echo "Flux root is missing Kustomization/$name" >&2
                missing=1
            fi
        done
        if ! yq ea 'select(.kind == "GitRepository" and .metadata.name == "flux-system") | .metadata.name' "$rendered" | grep -qx flux-system; then
            echo "Flux root is missing GitRepository/flux-system" >&2
            missing=1
        fi
        [ "$missing" -eq 0 ]
    }

    kubernetes_version="$(
        nix eval --impure --raw --expr '(import ./network/topology.nix).kubernetes.version'
    )"

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    rendered_files=()
    for root in "${roots[@]}"; do
        name="${root#deploy/k8s/}"
        name="${name//\//-}"
        raw="$tmp_dir/$name.raw.yaml"
        rendered="$tmp_dir/$name.yaml"

        printf '\n==> kustomize build %s\n' "$root"
        kustomize build "$root" > "$raw"
        sanitize_sops_metadata "$raw" "$rendered"
        rendered_files+=("$rendered")
    done

    run kubeconform -summary -strict -ignore-missing-schemas -kubernetes-version "$kubernetes_version" "${rendered_files[@]}"
    run kube-linter lint --exclude no-read-only-root-fs "${rendered_files[@]}"

    for rendered in "${rendered_files[@]}"; do
        require_default_deny bookorbit "$rendered"
        require_default_deny tonys-gis "$rendered"
        require_default_deny local-path-storage "$rendered"
        require_flux_root "$rendered"
    done

[private]
_check_shell:
    #!/usr/bin/env bash
    shell_roots=()
    for candidate in deploy/tools .githooks; do
        if [ -d "$candidate" ]; then
            shell_roots+=("$candidate")
        fi
    done

    mapfile -t shell_files < <(
        if [ "${#shell_roots[@]}" -gt 0 ]; then
            find "${shell_roots[@]}" -maxdepth 2 -type f \
                -not -path 'deploy/tools/completions/*' \
                | sort
        fi
    )

    if [ "${#shell_files[@]}" -eq 0 ]; then
        echo "No shell files found."
        exit 0
    fi

    shellcheck "${shell_files[@]}"

[private]
_check_yaml:
    yamllint \
        -d '{extends: relaxed, rules: {line-length: disable, indentation: disable}}' \
        .github \
        ansible \
        deploy/k8s

[private]
_check_actions:
    #!/usr/bin/env bash
    mapfile -t workflows < <(find .github/workflows .github/workflows.disabled -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)
    if [ "${#workflows[@]}" -eq 0 ]; then
        echo "No GitHub workflow YAML files found."
        exit 0
    fi
    actionlint "${workflows[@]}"

[private]
_check_secrets:
    #!/usr/bin/env bash
    max_nixpkgs_age_days="${MAX_NIXPKGS_AGE_DAYS:-30}"

    run() {
        printf '\n==> %s\n' "$*"
        "$@"
    }

    check_nixpkgs_age() {
        local last_modified now age_seconds age_days

        last_modified="$(
            nix eval --impure --raw --expr \
                'toString (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked.lastModified'
        )"
        now="$(date +%s)"
        age_seconds="$((now - last_modified))"
        age_days="$((age_seconds / 86400))"

        printf '\n==> nixpkgs lock age: %s days (max %s)\n' "$age_days" "$max_nixpkgs_age_days"
        if [ "$age_days" -gt "$max_nixpkgs_age_days" ]; then
            printf '%s\n' \
                "nixpkgs input is too old for flake-checker." \
                "Run:" \
                "  nix flake lock --update-input nixpkgs" >&2
            exit 1
        fi
    }

    check_worktree_secrets() {
        local tmp_dir

        tmp_dir="$(mktemp -d)"
        trap 'rm -rf "$tmp_dir"' RETURN

        while IFS= read -r -d '' path; do
            [ -f "$path" ] || continue
            mkdir -p "$tmp_dir/$(dirname "$path")"
            cp -p "$path" "$tmp_dir/$path"
        done < <(git ls-files -z --cached --modified --others --exclude-standard)

        run gitleaks dir "$tmp_dir" --redact
    }

    check_worktree_secrets
    check_nixpkgs_age

[private]
_check_docs:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t docs < <(rg --files -g '*.md')
    allowed='^(check|host|vm|k8s|gitops|manifest|nix|setup)$'
    legacy='just (plan|apply|status|ssh|gc|update|install-completions|install-hooks|ci|deploy|cd|cd-plan|bootstrap|reconcile|check-app|check-all|check-generated|clean-generated|diff-generated|platform|render|render-all|diff|clean|flux|check-(ci|nix|k8s|yaml|shell|actions|secrets)|deploy-(host|vm|node|all)|vm-(build|provision|start|stop|restart|destroy|cleanup|sync|status)|k8s-(deploy|reset-deploy|bootstrap|clean|verify)|flux-(bootstrap|status|reconcile)|net|build)\b'

    require_readme_topology_vms_current() {
        local expected actual
        expected="$(
            nix eval --impure --json --expr '(import ./network/topology.nix).vms' |
                jq -r 'to_entries[] | "\(.key) \(.value.ip)"' |
                sort
        )"
        actual="$(
            rg --only-matching 'k8s-(master|worker)-[0-9]+<br/>[0-9.]+' README.md |
                sed 's#<br/># #' |
                sort -u
        )"
        if [ "$actual" != "$expected" ]; then
            echo "README architecture VM/IP list does not match network/topology.nix." >&2
            echo "Expected:" >&2
            printf '%s\n' "$expected" >&2
            echo "Actual:" >&2
            printf '%s\n' "$actual" >&2
            exit 1
        fi
    }

    if rg -n "$legacy" "${docs[@]}"; then
        echo "Docs still reference legacy just recipes." >&2
        exit 1
    fi

    require_readme_topology_vms_current

    mapfile -t recipes < <(
        {
            rg --no-filename '^[[:space:]]*(CONFIRM_[A-Z_]+=homelab[[:space:]]+)?just[[:space:]]+[A-Za-z0-9_-]+' "${docs[@]}" |
                sed -E 's/^[[:space:]]*(CONFIRM_[A-Z_]+=homelab[[:space:]]+)?just[[:space:]]+([A-Za-z0-9_-]+).*/\2/' || true
            rg --only-matching --no-filename '`(CONFIRM_[A-Z_]+=homelab[[:space:]]+)?just[[:space:]]+[A-Za-z0-9_-]+' "${docs[@]}" |
                sed -E 's/^`(CONFIRM_[A-Z_]+=homelab[[:space:]]+)?just[[:space:]]+([A-Za-z0-9_-]+)/\2/' || true
        } | sort -u
    )
    for recipe in "${recipes[@]}"; do
        if ! [[ "$recipe" =~ $allowed ]]; then
            echo "Docs reference unknown public just recipe: $recipe" >&2
            exit 1
        fi
    done

[private]
_check_hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp_msg="$(mktemp)"
    trap 'rm -f "$tmp_msg"' EXIT

    printf '%s\n' 'fix(cni): validate local commit convention' > "$tmp_msg"
    .githooks/commit-msg "$tmp_msg"

    printf '%s\n' 'bad commit message' > "$tmp_msg"
    if .githooks/commit-msg "$tmp_msg" >/tmp/tonys-homelab-commitlint.err 2>&1; then
        echo "commit-msg hook accepted an invalid sample" >&2
        cat /tmp/tonys-homelab-commitlint.err >&2
        exit 1
    fi

[private]
_check_recipe_contracts:
    #!/usr/bin/env bash
    set -euo pipefail
    run() {
        printf '\n==> %s\n' "$*"
        "$@"
    }

    expect() {
        local expected="$1"
        shift
        local actual
        actual="$("$@")"
        if [ "$actual" != "$expected" ]; then
            echo "Expected: $expected" >&2
            echo "Actual:   $actual" >&2
            exit 1
        fi
    }

    expect_fail() {
        local out err
        out="$(mktemp)"
        err="$(mktemp)"
        if "$@" >"$out" 2>"$err"; then
            echo "Expected failure, command succeeded: $*" >&2
            cat "$out" >&2
            cat "$err" >&2
            rm -f "$out" "$err"
            exit 1
        fi
        rm -f "$out" "$err"
    }

    expect_confirm_failure() {
        env -u CONFIRM_DEPLOY \
            HOMELAB_JUST_STUB_REMOTE=1 \
            HOMELAB_JUST_STUB_LOG="$stub_log" \
            "$@"
    }

    expect_log() {
        local pattern="$1"
        local log="$2"
        if ! grep -Fqx "$pattern" "$log"; then
            echo "Missing expected stub log line: $pattern" >&2
            echo "Actual log:" >&2
            cat "$log" >&2
            exit 1
        fi
    }

    run zsh -n deploy/tools/completions/_just-homelab.zsh
    run zsh -n deploy/tools/completions/_just-dispatcher.zsh
    run fish -n deploy/tools/completions/just-completion-path.fish
    run fish -n deploy/tools/completions/just-homelab.fish
    run fish -n deploy/tools/completions/just-dispatcher.fish

    run fish -C 'source deploy/tools/completions/just-completion-path.fish' -c '
        test "$fish_complete_path[1]" = "$HOME/.config/fish/completions"
    '

    run fish -c '
        source deploy/tools/completions/just-dispatcher.fish
        complete -C "just host " | string match -qr "^ssh\\t"
    '

    run zsh -fc '
        autoload -Uz compinit
        compinit -D
        source deploy/tools/completions/_just-homelab.zsh
        source deploy/tools/completions/_just-dispatcher.zsh
        (( $+functions[_just] ))
        _describe() {
            local values_name="$4"
            print -l -- "${(@P)values_name}"
        }
        words=(just host "")
        CURRENT=3
        _just | grep -q "^ssh:"
    '

    fake_bin="$(mktemp -d)"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "{\"Peer\":[{\"HostName\":\"homelab-2\",\"DNSName\":\"homelab-2.example.ts.net.\",\"TailscaleIPs\":[\"100.64.0.2\"],\"Online\":true}]}"' > "$fake_bin/tailscale"
    printf '%s\n' '#!/usr/bin/env bash' 'test "${HOMELAB_TEST_LAN_REACHABLE:-}" = 1' > "$fake_bin/nc"
    chmod +x "$fake_bin/tailscale" "$fake_bin/nc"
    HOMELAB_TEST_LAN_REACHABLE=1 PATH="$fake_bin:$PATH" just --evaluate ssh-config >/dev/null
    ssh -G -F .cache/ssh-config homelab-2 | grep -qx 'hostname 192.168.45.83'
    HOMELAB_TEST_LAN_REACHABLE=0 PATH="$fake_bin:$PATH" just --evaluate ssh-config >/dev/null
    ssh -G -F .cache/ssh-config homelab-2 | grep -qx 'hostname 100.64.0.2'
    rm -rf "$fake_bin"

    summary="$(just --summary | tr ' ' '\n')"
    for recipe in check gitops host k8s manifest nix setup vm; do
        if ! grep -qx "$recipe" <<< "$summary"; then
            echo "Missing public recipe: $recipe" >&2
            exit 1
        fi
    done
    for recipe in plan apply status ssh gc update install-completions install-hooks bootstrap reconcile ci cd cd-plan deploy flux render render-all check-app check-all check-generated diff diff-generated clean clean-generated platform; do
        if grep -qx "$recipe" <<< "$summary"; then
            echo "Unexpected public recipe: $recipe" >&2
            exit 1
        fi
    done

    expect "homelab-1,homelab-2" just _topology_targets host-all
    expect "homelab-1" just _topology_targets host homelab-1
    expect "homelab-1" just _topology_targets homelab-1
    expect "homelab-2" just _topology_targets host homelab-2
    expect "homelab-2" just _topology_targets homelab-2
    expect "k8s-master-1" just _topology_targets vm k8s-master-1
    expect "k8s-master-1" just _topology_targets k8s-master-1
    expect "k8s-master-1,k8s-worker-1,k8s-worker-2" just _topology_targets vm-all
    expect "__all__" just _topology_targets all

    expect "homelab-1" just _deploy_targets host homelab-1
    expect "homelab-1,homelab-2" bash -c "just host list | paste -sd, -"

    stub_log="$(mktemp)"
    contract_home="$(mktemp -d)"
    trap 'rm -f "$stub_log"; rm -rf "$contract_home"' EXIT

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just host plan homelab-1
    expect_log "colmena apply dry-activate --no-keys --on homelab-1 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just host apply homelab-1
    expect_log "colmena apply dry-activate --no-keys --on homelab-1 --verbose" "$stub_log"
    expect_log "colmena apply --on homelab-1 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just host verify homelab-1
    expect_log "host verify homelab-1" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just host verify homelab-2
    expect_log "host verify homelab-2" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just host add homelab-2 root@192.168.45.173
    expect_log "host add homelab-2 root@192.168.45.173" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_INSTALL=homelab-2:/dev/nvme0n1 just host install homelab-2
    expect_log "nixos-anywhere homelab-2 root@192.168.45.83 /dev/nvme0n1" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just vm plan k8s-master-1
    expect_log "colmena apply dry-activate --no-keys --on k8s-master-1 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just vm apply k8s-master-1
    expect_log "colmena apply dry-activate --no-keys --on k8s-master-1 --verbose" "$stub_log"
    expect_log "colmena apply --on k8s-master-1 --verbose" "$stub_log"

    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just k8s check

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just k8s join homelab-2
    expect_log "k8s join k8s-master-1,homelab-2" "$stub_log"

    expect_fail just k8s join
    expect_fail just k8s join homelab-1

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just k8s reconcile homelab-2
    expect_log "k8s reconcile k8s-master-1,homelab-2" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just nix check

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just gitops reconcile
    expect_log "flux reconcile" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just gitops status
    expect_log "flux status" "$stub_log"

    run just manifest check-generated

    mkdir -p "$contract_home/.config/fish/completions" "$contract_home/.config/fish/conf.d" "$contract_home/.zfunc"
    printf 'foreign fish completion\n' > "$contract_home/.config/fish/completions/just.fish"
    printf 'foreign zsh completion\n' > "$contract_home/.zfunc/_just"
    run env HOME="$contract_home" just setup completions
    test -e "$contract_home/.config/fish/completions/just.fish"
    find "$contract_home/.config/fish/completions" -maxdepth 1 -name 'just.fish.bak.*' | grep -q .

    printf 'foreign fish completion\n' > "$contract_home/.config/fish/completions/just.fish"
    printf 'foreign zsh completion\n' > "$contract_home/.zfunc/_just"
    run env HOME="$contract_home" just setup completions

    expect_fail just _topology_targets host k8s-master-1
    expect_fail just _topology_targets vm homelab-1
    expect_fail just _topology_targets host unknown
    expect_fail just _topology_targets vm unknown
    expect_fail just _topology_targets unknown
    expect_fail just _topology_targets host-all homelab-1
    expect_fail just host unknown homelab-1
    expect_fail just host add homelab-3 root@192.168.45.29
    expect_fail just host install homelab-2
    expect_fail just vm ssh homelab-1
    expect_fail just vm plan
    expect_fail just nix unknown
    expect_fail just setup
    expect_fail just setup unknown
    expect_fail expect_confirm_failure just gitops reconcile
    expect_fail just gitops reconcile homelab-1
    expect_fail just gitops status extra
    expect_fail just plan infra host unknown
    expect_fail just apply gitops
    expect_fail just status gitops
    expect_fail just reconcile gitops
    expect_fail just bootstrap gitops flux
    expect_fail just flux reconcile
    expect_fail just manifest render a b
    expect_fail just _manifest render a b
    expect_fail just _manifest render-all tonys-gis
    expect_fail just _manifest check a b
    expect_fail just _manifest diff tonys-gis

[private]
_deploy_host:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _deploy_targets host-all)"
    just _colmena apply --on "$targets" --verbose

[private]
_deploy_host_plan:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _deploy_targets host-all)"
    echo "Target: hosts ($targets)"
    just _colmena apply dry-activate --no-keys --on "$targets" --verbose

[private]
_deploy_vm:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _deploy_targets vm-all)"
    just _colmena apply --on "$targets" --verbose

[private]
_deploy_vm_plan:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _deploy_targets vm-all)"
    echo "Target: vms ($targets)"
    just _colmena apply dry-activate --no-keys --on "$targets" --verbose

[private]
_deploy_nodes +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _deploy_targets node {{ nodes }})"
    just _colmena apply --on "$targets" --verbose

[private]
_deploy_nodes_plan +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets="$(just _deploy_targets node {{ nodes }})"
    echo "Target: nodes ($targets)"
    just _colmena apply dry-activate --no-keys --on "$targets" --verbose

[private]
_vm_build *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    remote_dir="/tmp/homelab-build"
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    target_system=$(nix eval --raw --impure '.#targetSystem')

    targets="{{ vms }}"
    if [ -z "$targets" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi
    if [ "$targets" = "all" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".parentHost")
        echo "=== Building $vm on $host (Target: $target_system) ==="
        ssh -n -F {{ ssh-config }} "$host" "rm -rf $remote_dir && mkdir -p $remote_dir"
        rsync -az --filter=':- .gitignore' --exclude='.git' -e "ssh -F {{ ssh-config }}" . "$host:$remote_dir/"
        ssh -n -F {{ ssh-config }} "$host" "cd $remote_dir && nix build --impure '.#packages.$target_system.$vm' --system $target_system -o /tmp/image-$vm"
        ssh -n -F {{ ssh-config }} "$host" "sudo mkdir -p /var/lib/libvirt/images/base && sudo cp /tmp/image-$vm/*.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
        ssh -n -F {{ ssh-config }} "$host" "rm -rf /tmp/image-$vm $remote_dir"
        echo "  $vm: OK"
    done

[private]
_vm_ssh name:
    #!/usr/bin/env bash
    set -euo pipefail
    just _topology_targets vm "{{ name }}" >/dev/null
    exec just _ssh_connect "{{ name }}"

[private]
_vm_plan +names:
    #!/usr/bin/env bash
    set -euo pipefail
    just _infra_plan vm {{ names }}

[private]
_vm_apply +names:
    #!/usr/bin/env bash
    set -euo pipefail
    just _topology_targets vm {{ names }} >/dev/null
    just _require_confirm_deploy "just vm apply {{ names }}"
    just _infra_plan vm {{ names }}
    just _deploy_resolved vm {{ names }}

[private]
_vm_provision *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    ssh_timeout_s="${PROVISION_SSH_TIMEOUT:-300}"

    targets="{{ vms }}"
    if [ -z "$targets" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi
    if [ "$targets" = "all" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".parentHost")
        ip=$(echo "$data" | jq -r ".\"$vm\".ip")
        echo "=== Provisioning $vm on $host ($ip) ==="
        ssh -n -F {{ ssh-config }} "$host" "sudo virsh destroy $vm 2>/dev/null || true; \
                           sudo rm -f /var/lib/libvirt/images/$vm.qcow2; \
                           sudo systemctl restart vm-$vm.service"

        printf "  Waiting for SSH..."
        start_ts=$(date +%s)
        while true; do
            if ssh -n -F {{ ssh-config }} "$host" "nc -zvw1 $ip 22" &>/dev/null; then echo " OK"; break; fi
            if [ $(( $(date +%s) - start_ts )) -ge "$ssh_timeout_s" ]; then echo " TIMEOUT"; exit 1; fi
            sleep 2; printf "."
        done
    done

[private]
_vm_systemctl action *names:
    #!/usr/bin/env bash
    set -euo pipefail
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    targets="{{ names }}"
    if [ -z "$targets" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi
    if [ "$targets" = "all" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi
    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".parentHost")
        echo "$vm: {{ action }} on $host..."
        just _ssh "$host" "sudo systemctl {{ action }} vm-$vm.service" &
    done
    wait

[private]
_vm_destroy +names:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${CONFIRM_DESTROY:-}" != "homelab" ]; then
        echo "Refusing destructive VM destroy."
        echo "Run with: CONFIRM_DESTROY=homelab just vm destroy <name|all>"
        exit 2
    fi

    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    targets="{{ names }}"
    if [ "$targets" = "all" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi
    if [ -z "$targets" ]; then
        echo "Usage: CONFIRM_DESTROY=homelab just vm destroy <name|all>" >&2
        exit 2
    fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".parentHost")
        echo "$vm: destroying on $host..."
        just _ssh "$host" "sudo systemctl stop vm-$vm.service 2>/dev/null || true; \
            sudo virsh destroy $vm 2>/dev/null || true; \
            sudo virsh undefine $vm --remove-all-storage 2>/dev/null || true; \
            sudo rm -f /var/lib/libvirt/images/$vm.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
    done

[private]
_vm_cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    expected=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r '.[]' | sort)

    for host in $(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]'); do
        actual=$(just _ssh "$host" "sudo virsh list --all --name" | grep -v '^$' | sort)
        stale=$(comm -23 <(echo "$actual") <(echo "$expected"))

        if [ -z "$stale" ]; then
            echo "$host: clean"
            continue
        fi

        echo "$host: stale VMs found -> $stale"
        for vm in $stale; do
            read -r -p "  Remove $vm? [y/N] " confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                just _ssh "$host" "sudo virsh destroy $vm 2>/dev/null || true; \
                    sudo virsh undefine $vm --remove-all-storage 2>/dev/null || true; \
                    sudo rm -f /var/lib/libvirt/images/$vm.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
                echo "  $vm: removed"
            fi
        done
    done

[private]
_vm_status *names:
    #!/usr/bin/env bash
    set -euo pipefail
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    targets="{{ names }}"
    if [ "$targets" = "all" ]; then targets=""; fi
    if [ -n "$targets" ]; then
        echo "$data" | jq --arg names "$targets" -r '
          ($names | split(" ")) as $want |
          to_entries[] | select(.key as $name | $want | index($name)) | "\(.key) \(.value.ip) \(.value.parentHost)"
        '
    else
        echo "$data" | jq -r 'to_entries[] | "\(.key) \(.value.ip) \(.value.parentHost)"'
    fi | while read -r name ip host; do
        if just _ssh "$host" "nc -zvw2 $ip 22" &>/dev/null; then
            echo "  $name ($ip) on $host: OK"
        else
            echo "  $name ($ip) on $host: UNREACHABLE"
        fi
    done

[private]
_k8s_bootstrap:
    just _ansible ansible/site.yml --tags bootstrap -v

[private]
_k8s_ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    master="$(nix eval --impure --json --expr '(import {{ topology }}).vms' | jq -r 'to_entries[] | select(.value.role == "k8s-master") | .key' | head -1)"
    if [ -z "$master" ]; then
        echo "No Kubernetes master VM found in topology." >&2
        exit 2
    fi
    exec just _ssh_connect "$master"

[private]
_k8s_limit target:
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{ target }}"
    if [ -z "$target" ]; then
        echo "Usage: just k8s join <node|all>" >&2
        echo "Example: just k8s join homelab-2" >&2
        exit 2
    fi

    inventory_json="$(nix eval --impure --json --expr 'import ./ansible/inventory.nix {}')"
    master="$(jq -r '.k8s_masters.hosts[0] // empty' <<< "$inventory_json")"
    if [ -z "$master" ]; then
        echo "No Kubernetes master found in Ansible inventory." >&2
        exit 2
    fi

    if [ "$target" = "all" ]; then
        jq -r '([.k8s_masters.hosts[], .k8s_workers.hosts[]] | unique | join(","))' <<< "$inventory_json"
        exit 0
    fi

    if ! jq -e --arg target "$target" '([.k8s_masters.hosts[], .k8s_workers.hosts[]] | index($target)) != null' <<< "$inventory_json" >/dev/null; then
        echo "Unknown Kubernetes node: $target" >&2
        echo "Known Kubernetes nodes: $(jq -r '([.k8s_masters.hosts[], .k8s_workers.hosts[]] | join(", "))' <<< "$inventory_json")" >&2
        exit 2
    fi

    if [ "$target" = "$master" ]; then
        printf '%s\n' "$master"
    else
        printf '%s,%s\n' "$master" "$target"
    fi

[private]
_k8s_join target="":
    #!/usr/bin/env bash
    set -euo pipefail
    limit="$(just _k8s_limit "{{ target }}")"
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'k8s join %s\n' "$limit" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    echo "Target: k8s join ({{ target }} -> $limit)"
    echo "Action: run idempotent kubeadm bootstrap/join for nodes not yet joined."
    just _ansible ansible/site.yml --tags bootstrap --limit "$limit" -v

[private]
_k8s_reconcile target="":
    #!/usr/bin/env bash
    set -euo pipefail
    limit="$(just _k8s_limit "{{ target }}")"
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'k8s reconcile %s\n' "$limit" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    echo "Target: k8s reconcile ({{ target }} -> $limit)"
    echo "Action: validate manifests, converge kubeadm membership, then verify runtime."
    just check k8s
    just _k8s_join "{{ target }}"
    just _k8s_verify

[private]
_k8s_clean:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${CONFIRM_RESET:-}" != "homelab" ]; then
        echo "Refusing destructive Kubernetes reset."
        echo "This removes /etc/kubernetes, /var/lib/etcd, /var/lib/kubelet, /etc/cni/net.d, and kubelet drop-ins."
        echo "Run with: CONFIRM_RESET=homelab just k8s clean"
        exit 2
    fi
    just _ansible ansible/site.yml --tags cleanup -e reset_cluster=true -v

[private]
_k8s_verify:
    #!/usr/bin/env bash
    set -euo pipefail
    master_ip=$(just _master_ip)
    api_vip=$(nix eval --impure --raw --expr '(import {{ topology }}).kubernetes.api_vip')

    kc() { ssh -F {{ ssh-config }} "$master_ip" "$*" 2>/dev/null; }

    echo "=== API Health (VIP: $api_vip) ==="
    kc "curl -sk https://$api_vip:6443/healthz" && echo " OK" || echo " UNHEALTHY"
    echo ""
    echo "=== Nodes ==="
    kc "kubectl get nodes -o wide" || echo "unavailable"
    echo ""
    echo "=== kube-system Pods ==="
    kc "kubectl get pods -n kube-system -o wide" || echo "unavailable"

[private]
_k8s_sops_age_expected_recipient:
    #!/usr/bin/env bash
    set -euo pipefail
    awk '/&cluster[[:space:]]+age1/ { print $3; found = 1 } END { if (!found) exit 1 }' .sops.yaml

[private]
_k8s_sops_age_key_file:
    #!/usr/bin/env bash
    set -euo pipefail
    key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/bookorbit-cluster.agekey}"
    if [ ! -f "$key_file" ]; then
        echo "Missing cluster age private key: $key_file" >&2
        echo "Set SOPS_AGE_KEY_FILE or restore the key from the password manager." >&2
        exit 2
    fi
    printf '%s\n' "$key_file"

[private]
_k8s_verify_local_sops_age_key:
    #!/usr/bin/env bash
    set -euo pipefail
    key_file="$(just _k8s_sops_age_key_file)"
    expected="$(just _k8s_sops_age_expected_recipient)"
    actual="$(age-keygen -y "$key_file")"
    if [ "$actual" != "$expected" ]; then
        echo "Cluster age private key does not match .sops.yaml cluster recipient." >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 2
    fi
    echo "Local cluster age key matches .sops.yaml: $actual"

[private]
_k8s_bootstrap_sops_age:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'k8s bootstrap sops-age\n' >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi

    key_file="$(just _k8s_sops_age_key_file)"
    just _k8s_verify_local_sops_age_key

    master_ip=$(just _master_ip)
    ssh -F {{ ssh-config }} "$master_ip" '
        set -euo pipefail
        tmp="$(mktemp)"
        trap "rm -f \"$tmp\"" EXIT
        umask 077
        cat > "$tmp"
        kubectl -n flux-system create secret generic sops-age \
            --from-file=age.agekey="$tmp" \
            --dry-run=client -o yaml | kubectl apply -f -
    ' < "$key_file"
    just _k8s_verify_sops_age

[private]
_k8s_verify_sops_age:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'k8s verify sops-age\n' >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi

    expected="$(just _k8s_sops_age_expected_recipient)"
    master_ip=$(just _master_ip)
    actual="$(
        ssh -F {{ ssh-config }} "$master_ip" \
            "kubectl -n flux-system get secret sops-age -o jsonpath='{.data.age\\.agekey}'" |
            base64 -d |
            age-keygen -y /dev/stdin
    )"
    if [ "$actual" != "$expected" ]; then
        echo "flux-system/sops-age does not match .sops.yaml cluster recipient." >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 2
    fi
    echo "Cluster sops-age Secret matches .sops.yaml: $actual"

[private]
_flux_bootstrap owner repo="tonys-homelab" branch="main":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'flux bootstrap owner=%s repo=%s branch=%s\n' "{{ owner }}" "{{ repo }}" "{{ branch }}" >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    master_ip=$(just _master_ip)
    printf '%s\n' "$GITHUB_TOKEN" | ssh -F {{ ssh-config }} "$master_ip" "read -r GITHUB_TOKEN; export GITHUB_TOKEN; flux bootstrap github \
        --owner={{ owner }} \
        --repository={{ repo }} \
        --branch={{ branch }} \
        --path=deploy/k8s/clusters/homelab \
        --personal"

[private]
_flux_status:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'flux status\n' >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    master_ip=$(just _master_ip)
    ssh -F {{ ssh-config }} "$master_ip" "flux get all"

[private]
_flux_reconcile:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${HOMELAB_JUST_STUB_REMOTE:-}" = "1" ]; then
        printf 'flux reconcile\n' >> "${HOMELAB_JUST_STUB_LOG:?}"
        exit 0
    fi
    master_ip=$(just _master_ip)
    ssh -F {{ ssh-config }} "$master_ip" "flux reconcile source git flux-system && flux reconcile kustomization flux-system"
