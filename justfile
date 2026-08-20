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
  nix_data=$(nix eval --impure --json --expr 'let t = import ./network/topology.nix; in { inherit (t) hosts vms wan dns vlans tailscale kubernetes storage; }')
  ts_data_raw=$(tailscale status --json 2>/dev/null || true)
  if echo "$ts_data_raw" | jq -e . >/dev/null 2>&1; then
    ts_data="$ts_data_raw"
  else
    ts_data='{"Peer":[]}'
  fi

  # 물리 호스트 및 VM 설정 생성
  echo "$nix_data" | jq -r --argjson ts "$ts_data" '
    (.hosts | to_entries[] as $host |
      (($ts.Peer[]? | select(.HostName == $host.key or (.DNSName | startswith($host.key+"."))) | .TailscaleIPs[0]) // $host.value.ip) as $ip |
      "Host \($host.key)\n    HostName \($ip)\n    User \($host.value.user)\n    StrictHostKeyChecking no\n"),
    (.vms | to_entries[] as $vm |
      "Host \($vm.key) \($vm.value.ip)\n    HostName \($vm.value.ip)\n    User root\n    ProxyJump \($vm.value.parentHost)\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n")
  ' > "$config_file"

  echo "$config_file"
```

# Deprecated alias for `just check`.
ci target="all":
    @just _warn_deprecated "just ci {{ target }}" "just check {{ target }}"
    just check "{{ target }}"

# Plan before remote mutation. Targets: gitops, infra all, infra host <name...>, infra vm <name...>.
plan target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            if [ -n "{{ args }}" ]; then
                echo "Target 'gitops' does not accept extra arguments: {{ args }}" >&2
                exit 2
            fi
            echo "Target: gitops"
            echo "Action: run local checks before reconciling GitOps-owned manifests."
            just check
            echo "Plan OK. To reconcile via Flux: CONFIRM_DEPLOY=homelab just apply gitops"
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

# Apply after checks and explicit confirmation. Targets: gitops, infra all, infra host <name...>, infra vm <name...>.
apply target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            if [ -n "{{ args }}" ]; then
                echo "Target 'gitops' does not accept extra arguments: {{ args }}" >&2
                exit 2
            fi
            just _require_confirm_deploy "just apply gitops"
            just plan gitops
            just _gitops_reconcile
            ;;
        infra)
            just _topology_targets {{ args }} >/dev/null
            just _require_confirm_deploy "just apply infra {{ args }}"
            just plan infra {{ args }}
            just _deploy_resolved {{ args }}
            ;;
        all|host-all|hosts|vm-all|vms|host|vm|node|nodes)
            just _topology_targets "{{ target }}" {{ args }} >/dev/null
            just _require_confirm_deploy "just apply infra {{ target }} {{ args }}"
            just plan infra "{{ target }}" {{ args }}
            just _deploy_resolved "{{ target }}" {{ args }}
            ;;
        *)
            just _topology_targets "{{ target }}" {{ args }} >/dev/null
            just _require_confirm_deploy "just apply infra {{ target }} {{ args }}"
            just plan infra "{{ target }}" {{ args }}
            just _deploy_resolved "{{ target }}" {{ args }}
            ;;
    esac

# Deprecated alias for `just plan`.
cd-plan target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just cd-plan {{ target }} {{ args }}" "just plan {{ target }} {{ args }}"
    just plan "{{ target }}" {{ args }}

# Deprecated alias for `just apply`.
cd target *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just cd {{ target }} {{ args }}" "just apply {{ target }} {{ args }}"
    just apply "{{ target }}" {{ args }}

# Run local guard checks. Targets: all, nix, k8s, yaml, shell, actions, secrets, docs, hooks, recipes.
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
            for item in nix k8s yaml shell actions secrets docs hooks recipes; do
                printf '\n==> just check %s\n' "$item"
                just check "$item"
            done
            printf '\nAll local CI checks passed.\n'
            ;;
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
            echo "Expected one of: all, nix, k8s, yaml, shell, actions, secrets, docs, hooks, recipes" >&2
            exit 2
            ;;
    esac

# Deprecated direct deploy path. Prefer `just apply infra ...`.
deploy target="all" *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just deploy {{ target }} {{ nodes }}" "CONFIRM_DEPLOY=homelab just apply infra {{ target }} {{ nodes }}"
    just apply infra "{{ target }}" {{ nodes }}

# Manage VMs. Actions: status, start, stop, restart, build, provision, destroy, cleanup, sync.
vm action="status" *names:
    #!/usr/bin/env bash
    case "{{ action }}" in
        status) just _vm_status {{ names }} ;;
        start) just _vm_systemctl start {{ names }} ;;
        stop) just _vm_systemctl stop {{ names }} ;;
        restart) just _vm_systemctl restart {{ names }} ;;
        build) just _vm_build {{ names }} ;;
        provision) just _vm_provision {{ names }} ;;
        destroy) just _vm_destroy {{ names }} ;;
        cleanup) just _vm_cleanup ;;
        sync) just _vm_cleanup && just _vm_build {{ names }} && just _vm_provision {{ names }} ;;
        *)
            echo "Unknown VM action: {{ action }}" >&2
            echo "Expected one of: status, start, stop, restart, build, provision, destroy, cleanup, sync" >&2
            exit 2
            ;;
    esac

# Manage Kubernetes cluster lifecycle. Actions: verify, bootstrap, deploy, clean, reset-deploy.
k8s action="verify":
    #!/usr/bin/env bash
    case "{{ action }}" in
        verify) just _k8s_verify ;;
        bootstrap) just _k8s_bootstrap ;;
        deploy) just _k8s_bootstrap && just _k8s_verify ;;
        clean) just _k8s_clean ;;
        reset-deploy) just _k8s_clean && just _k8s_bootstrap && just _k8s_verify ;;
        *)
            echo "Unknown Kubernetes action: {{ action }}" >&2
            echo "Expected one of: verify, bootstrap, deploy, clean, reset-deploy" >&2
            exit 2
            ;;
    esac

# Show provider-neutral status. Targets: gitops.
status target="gitops" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            if [ -n "{{ args }}" ]; then
                echo "Target 'gitops' does not accept extra arguments: {{ args }}" >&2
                exit 2
            fi
            just _gitops_status
            ;;
        *)
            echo "Unknown status target: {{ target }}" >&2
            echo "Expected one of: gitops" >&2
            exit 2
            ;;
    esac

# Trigger provider-neutral reconciliation. Targets: gitops.
reconcile target="gitops" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            if [ -n "{{ args }}" ]; then
                echo "Target 'gitops' does not accept extra arguments: {{ args }}" >&2
                exit 2
            fi
            just _require_confirm_deploy "just reconcile gitops"
            just _gitops_reconcile
            ;;
        *)
            echo "Unknown reconcile target: {{ target }}" >&2
            echo "Expected one of: gitops" >&2
            exit 2
            ;;
    esac

# Deprecated provider-specific alias. Prefer `status/reconcile/bootstrap gitops`.
flux action="status" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        status)
            just _warn_deprecated "just flux status" "just status gitops"
            just _gitops_status
            ;;
        bootstrap)
            just _warn_deprecated "just flux bootstrap {{ args }}" "CONFIRM_DEPLOY=homelab just bootstrap gitops flux {{ args }}"
            just _require_confirm_deploy "just bootstrap gitops flux {{ args }}"
            just _flux_bootstrap {{ args }}
            ;;
        reconcile)
            just _warn_deprecated "just flux reconcile" "CONFIRM_DEPLOY=homelab just reconcile gitops"
            just _require_confirm_deploy "just reconcile gitops"
            just _gitops_reconcile
            ;;
        *)
            echo "Unknown Flux action: {{ action }}" >&2
            echo "Expected one of: status, bootstrap, reconcile" >&2
            exit 2
            ;;
    esac

# Bootstrap provider-backed systems. Targets: gitops flux <owner> [repo] [branch].
bootstrap target="gitops" provider="flux" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        gitops)
            case "{{ provider }}" in
                flux)
                    just _require_confirm_deploy "just bootstrap gitops flux {{ args }}"
                    just _flux_bootstrap {{ args }}
                    ;;
                *)
                    echo "Unknown GitOps bootstrap provider: {{ provider }}" >&2
                    echo "Expected one of: flux" >&2
                    exit 2
                    ;;
            esac
            ;;
        *)
            echo "Unknown bootstrap target: {{ target }}" >&2
            echo "Expected one of: gitops" >&2
            exit 2
            ;;
    esac

# Manage repo-owned manifest artifacts. Actions: render, render-all, check, check-all, check-generated, diff, clean.
manifest action="render" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
        render|render-all|check|check-all|check-generated|diff|clean) just _manifest "{{ action }}" {{ args }} ;;
        *)
            echo "Unknown manifest action: {{ action }}" >&2
            echo "Expected one of: render, render-all, check, check-all, check-generated, diff, clean" >&2
            exit 2
            ;;
    esac

# Deprecated alias for `just manifest render`.
render target="manifest" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just render {{ target }} {{ args }}" "just manifest render {{ args }}"
    case "{{ target }}" in
        manifest) just _manifest render {{ args }} ;;
        manifest-all|manifests) just _manifest render-all {{ args }} ;;
        *) just _manifest render "{{ target }}" {{ args }} ;;
    esac

# Deprecated alias for `just manifest diff`.
diff target="manifest" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just diff {{ target }} {{ args }}" "just manifest diff"
    case "{{ target }}" in
        manifest|manifests) just _manifest diff {{ args }} ;;
        *)
            echo "Unknown diff target: {{ target }}" >&2
            echo "Expected one of: manifest" >&2
            exit 2
            ;;
    esac

# Deprecated alias for `just manifest clean`.
clean target="manifest" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just clean {{ target }} {{ args }}" "just manifest clean"
    case "{{ target }}" in
        manifest|manifests) just _manifest clean {{ args }} ;;
        *)
            echo "Unknown clean target: {{ target }}" >&2
            echo "Expected one of: manifest" >&2
            exit 2
            ;;
    esac

# Deprecated alias for `just manifest`.
platform action="render" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just platform {{ action }} {{ args }}" "just manifest {{ action }} {{ args }}"
    just _manifest "{{ action }}" {{ args }}

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
            echo "Usage: just manifest {{ action }} [app]" >&2
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

# Deprecated alias for `just manifest render-all`.
render-all:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just render-all" "just manifest render-all"
    just manifest render-all

# Deprecated alias for `just manifest check`.
check-app app="${APP:-tonys-gis}":
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just check-app {{ app }}" "just manifest check {{ app }}"
    just manifest check "{{ app }}"

# Deprecated alias for `just manifest check-all`.
check-all:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just check-all" "just manifest check-all"
    just _manifest check-all

# Deprecated alias for `just manifest check-generated`.
check-generated:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just check-generated" "just manifest check-generated"
    just manifest check-generated

# Deprecated alias for `just manifest diff`.
diff-generated:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just diff-generated" "just manifest diff"
    just manifest diff

# Deprecated alias for `just manifest clean`.
clean-generated:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn_deprecated "just clean-generated" "just manifest clean"
    just manifest clean

# Connect to node managed by colmena using generated SSH config.
ssh node:
    ssh -F {{ ssh-config }} {{ node }}

# Garbage collection on all or selected nodes. Targets: all, host-all, vm-all, host <name...>, vm <name...>.
gc target="all" *nodes:
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
update:
    nix flake update

# Install repository-managed git hooks locally.
install-hooks:
    npm ci
    npx --no-install husky

# Install shell completions for topology-aware homelab just commands.
install-completions:
    #!/usr/bin/env bash
    set -euo pipefail
    install_completion() {
        local src="$1" dest="$2"
        mkdir -p "$(dirname "$dest")"
        if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
            if [ "${CONFIRM_INSTALL_COMPLETIONS:-}" != "homelab" ] && [ "${FORCE:-}" != "1" ]; then
                echo "Refusing to overwrite existing completion: $dest" >&2
                echo "Run with CONFIRM_INSTALL_COMPLETIONS=homelab or FORCE=1 to overwrite." >&2
                exit 2
            fi
            cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
        fi
        cp "$src" "$dest"
    }

    mkdir -p "$HOME/.config/fish/completions" "$HOME/.zfunc"
    install_completion completions/just-homelab.fish "$HOME/.config/fish/completions/just.fish"
    install_completion completions/_just-homelab.zsh "$HOME/.zfunc/_just"
    echo "Installed fish completion: $HOME/.config/fish/completions/just.fish"
    echo "Installed zsh completion:  $HOME/.zfunc/_just"
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
_warn_deprecated old new:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Deprecated just command: {{ old }}" >&2
    echo "Use instead: {{ new }}" >&2

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
_check_k8s:
    #!/usr/bin/env bash
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

    run kyverno version

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    rendered_files=()
    policy_files=()
    for root in "${roots[@]}"; do
        name="${root#deploy/k8s/}"
        name="${name//\//-}"
        raw="$tmp_dir/$name.raw.yaml"
        rendered="$tmp_dir/$name.yaml"
        policy_input="$tmp_dir/$name.policy.yaml"

        printf '\n==> kustomize build %s\n' "$root"
        kustomize build "$root" > "$raw"
        sanitize_sops_metadata "$raw" "$rendered"
        yq ea 'select(.kind == "Pod" or .kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "ReplicaSet" or .kind == "Job" or .kind == "CronJob" or .kind == "Gateway")' "$rendered" > "$policy_input"
        rendered_files+=("$rendered")
        policy_files+=("$policy_input")
    done

    run kubeconform -summary -strict -ignore-missing-schemas -kubernetes-version "$kubernetes_version" "${rendered_files[@]}"
    run kube-linter lint --exclude no-read-only-root-fs "${rendered_files[@]}"
    run kyverno apply deploy/policy/k8s/kyverno/policies --resource "${policy_files[@]}"
    run kyverno test deploy/policy/k8s/kyverno --require-tests

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
    for candidate in deploy/tools .githooks .husky; do
        if [ -d "$candidate" ]; then
            shell_roots+=("$candidate")
        fi
    done

    mapfile -t shell_files < <(
        if [ "${#shell_roots[@]}" -gt 0 ]; then
            find "${shell_roots[@]}" -maxdepth 2 -type f \
                -not -path '.husky/_/*' \
                -not -path '.husky/_' | sort
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
        deploy/k8s \
        deploy/policy

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
    allowed='^(plan|apply|check|manifest|bootstrap|status|reconcile|vm|k8s|ssh|gc|update|install-completions|install-hooks)$'
    legacy='just (ci|deploy|cd|cd-plan|check-app|check-all|check-generated|clean-generated|diff-generated|platform|render-all|flux|check-(ci|nix|k8s|yaml|shell|actions|secrets)|deploy-(host|vm|node|all)|vm-(build|provision|start|stop|restart|destroy|cleanup|sync|status)|k8s-(deploy|reset-deploy|bootstrap|clean|verify)|flux-(bootstrap|status|reconcile)|net|build)\b'

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
    npm ci --ignore-scripts
    printf '%s\n' 'fix(cni): validate local commit convention' | npx --no-install commitlint
    if printf '%s\n' 'bad commit message' | npx --no-install commitlint >/tmp/tonys-homelab-commitlint.err 2>&1; then
        echo "commitlint accepted an invalid sample" >&2
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

    run zsh -n completions/_just-homelab.zsh
    run fish -n completions/just-homelab.fish

    summary="$(just --summary | tr ' ' '\n')"
    for recipe in plan apply manifest bootstrap status reconcile ci cd cd-plan deploy flux render render-all check-app check-all check-generated diff diff-generated clean clean-generated platform; do
        if ! grep -qx "$recipe" <<< "$summary"; then
            echo "Missing public recipe: $recipe" >&2
            exit 1
        fi
    done

    expect "homelab-1" just _topology_targets host-all
    expect "homelab-1" just _topology_targets host homelab-1
    expect "homelab-1" just _topology_targets homelab-1
    expect "k8s-master-1" just _topology_targets vm k8s-master-1
    expect "k8s-master-1" just _topology_targets k8s-master-1
    expect "k8s-master-1,k8s-worker-1,k8s-worker-2" just _topology_targets vm-all
    expect "__all__" just _topology_targets all

    expect "homelab-1" just _deploy_targets host homelab-1

    stub_log="$(mktemp)"
    contract_home="$(mktemp -d)"
    trap 'rm -f "$stub_log"; rm -rf "$contract_home"' EXIT

    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just apply infra host homelab-1
    expect_log "colmena apply dry-activate --no-keys --on homelab-1 --verbose" "$stub_log"
    expect_log "colmena apply --on homelab-1 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" just plan homelab-1
    expect_log "colmena apply dry-activate --no-keys --on homelab-1 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just apply homelab-1
    expect_log "colmena apply dry-activate --no-keys --on homelab-1 --verbose" "$stub_log"
    expect_log "colmena apply --on homelab-1 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just apply infra
    expect_log "colmena apply --on homelab-1 --verbose" "$stub_log"
    expect_log "colmena apply --on k8s-master-1,k8s-worker-1,k8s-worker-2 --verbose" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just apply gitops
    expect_log "flux reconcile" "$stub_log"

    : > "$stub_log"
    run env HOMELAB_JUST_STUB_REMOTE=1 HOMELAB_JUST_STUB_LOG="$stub_log" CONFIRM_DEPLOY=homelab just bootstrap gitops flux vanillacake369 tonys-homelab main
    expect_log "flux bootstrap owner=vanillacake369 repo=tonys-homelab branch=main" "$stub_log"

    mkdir -p "$contract_home/.config/fish/completions" "$contract_home/.zfunc"
    printf 'foreign fish completion\n' > "$contract_home/.config/fish/completions/just.fish"
    printf 'foreign zsh completion\n' > "$contract_home/.zfunc/_just"
    expect_fail env HOME="$contract_home" just install-completions
    run env HOME="$contract_home" CONFIRM_INSTALL_COMPLETIONS=homelab just install-completions
    test -e "$contract_home/.config/fish/completions/just.fish"
    find "$contract_home/.config/fish/completions" -maxdepth 1 -name 'just.fish.bak.*' | grep -q .

    expect_fail just _topology_targets host k8s-master-1
    expect_fail just _topology_targets vm homelab-1
    expect_fail just _topology_targets host unknown
    expect_fail just _topology_targets vm unknown
    expect_fail just _topology_targets unknown
    expect_fail just _topology_targets host-all homelab-1
    expect_fail just plan infra host unknown
    expect_fail just plan infra host
    expect_fail expect_confirm_failure just deploy host homelab-1
    expect_fail expect_confirm_failure just apply gitops
    expect_fail just apply gitops homelab-1
    expect_fail just status gitops extra
    expect_fail expect_confirm_failure just reconcile gitops
    expect_fail expect_confirm_failure just bootstrap gitops flux
    expect_fail expect_confirm_failure just flux reconcile
    expect_fail just platform nope
    expect_fail just manifest render a b
    expect_fail just manifest render-all tonys-gis
    expect_fail just manifest check a b
    expect_fail just manifest diff tonys-gis

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
