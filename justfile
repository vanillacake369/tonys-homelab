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

# Run the local CI-equivalent checks.
ci target="all":
    just check "{{ target }}"

# Plan a local deployment without applying changes. Targets: gitops, hosts, vms, node.
cd-plan target *nodes:
    #!/usr/bin/env bash
    case "{{ target }}" in
        gitops)
            just ci
            echo "Target: gitops"
            echo "Action: render and validate Flux-owned manifests only."
            just check k8s
            echo "Plan OK. To reconcile via Flux: CONFIRM_DEPLOY=homelab just cd gitops"
            ;;
        hosts|host)
            just ci
            just _deploy_host_plan
            ;;
        vms|vm)
            just ci
            just _deploy_vm_plan
            ;;
        node|nodes)
            if [ -z "{{ nodes }}" ]; then
                echo "Usage: just cd-plan node <node> [node...]" >&2
                exit 2
            fi
            just ci
            just _deploy_nodes_plan {{ nodes }}
            ;;
        *)
            echo "Unknown CD target: {{ target }}" >&2
            echo "Expected one of: gitops, hosts, vms, node" >&2
            exit 2
            ;;
    esac

# Apply a local deployment after CI and an explicit confirmation.
cd target *nodes:
    #!/usr/bin/env bash
    if [ "${CONFIRM_DEPLOY:-}" != "homelab" ]; then
        echo "Refusing deploy without explicit confirmation." >&2
        echo "Run: CONFIRM_DEPLOY=homelab just cd {{ target }} {{ nodes }}" >&2
        exit 2
    fi

    case "{{ target }}" in
        gitops)
            just cd-plan gitops
            just flux reconcile
            ;;
        hosts|host)
            just cd-plan hosts
            just deploy hosts
            ;;
        vms|vm)
            just cd-plan vms
            just deploy vms
            ;;
        node|nodes)
            if [ -z "{{ nodes }}" ]; then
                echo "Usage: CONFIRM_DEPLOY=homelab just cd node <node> [node...]" >&2
                exit 2
            fi
            just cd-plan node {{ nodes }}
            just deploy node {{ nodes }}
            ;;
        *)
            echo "Unknown CD target: {{ target }}" >&2
            echo "Expected one of: gitops, hosts, vms, node" >&2
            exit 2
            ;;
    esac

# Run local guard checks. Targets: all, nix, k8s, yaml, shell, actions, secrets, docs, hooks.
check target="all":
    #!/usr/bin/env bash
    if [ -z "${IN_NIX_SHELL:-}" ]; then
        exec nix develop -c just check "{{ target }}"
    fi

    case "{{ target }}" in
        all)
            for item in nix k8s yaml shell actions secrets docs hooks; do
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
        *)
            echo "Unknown check target: {{ target }}" >&2
            echo "Expected one of: all, nix, k8s, yaml, shell, actions, secrets, docs, hooks" >&2
            exit 2
            ;;
    esac

# Deploy hosts, VMs, all nodes, or selected node names.
deploy target="all" *nodes:
    #!/usr/bin/env bash
    case "{{ target }}" in
        all) just _deploy_host && just _deploy_vm ;;
        hosts|host) just _deploy_host ;;
        vms|vm) just _deploy_vm ;;
        node|nodes)
            if [ -z "{{ nodes }}" ]; then
                echo "Usage: just deploy node <node> [node...]" >&2
                exit 2
            fi
            just _deploy_nodes {{ nodes }}
            ;;
        *)
            if [ -n "{{ nodes }}" ]; then
                just _deploy_nodes {{ target }} {{ nodes }}
            else
                just _deploy_nodes {{ target }}
            fi
            ;;
    esac

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

# Manage Flux. Actions: status, bootstrap, reconcile.
flux action="status" *args:
    #!/usr/bin/env bash
    case "{{ action }}" in
        status) just _flux_status ;;
        bootstrap) just _flux_bootstrap {{ args }} ;;
        reconcile) just _flux_reconcile ;;
        *)
            echo "Unknown Flux action: {{ action }}" >&2
            echo "Expected one of: status, bootstrap, reconcile" >&2
            exit 2
            ;;
    esac

# Render one platform app from deploy/platform/apps/*.cue into deploy/k8s/generated/apps/<app>.
render app="${APP:-tonys-gis}":
    ./deploy/tools/platform-render.sh render "{{ app }}"

# Render all platform apps.
render-all:
    ./deploy/tools/platform-render.sh render-all

# Check one platform app render, validation, negative fixtures, and determinism.
check-app app="${APP:-tonys-gis}":
    ./deploy/tools/platform-render.sh check "{{ app }}"

# Check all platform apps.
check-all:
    ./deploy/tools/platform-render.sh check-all

# Verify committed generated output is up to date.
check-generated:
    ./deploy/tools/platform-render.sh check-generated

# Show generated output drift.
diff-generated:
    ./deploy/tools/platform-render.sh diff-generated

# Remove generated platform output.
clean-generated:
    ./deploy/tools/platform-render.sh clean-generated

# Connect to node managed by colmena using generated SSH config.
ssh node:
    ssh -F {{ ssh-config }} {{ node }}

# Garbage collection on all or selected nodes.
gc *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(if [ -z "{{ nodes }}" ]; then nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)' | jq -r '.[]'; else echo "{{ nodes }}"; fi)
    for node in $targets; do
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

[private]
_colmena +args:
    SSH_CONFIG_FILE={{ ssh-config }} nix run --impure .#colmena -- {{ args }}

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
    docs=(
        README.md
        ansible/README.md
        deploy/k8s/README.md
        deploy/k8s/docs/bookorbit-onboarding.md
        docs/runbooks/magicdns-gitops-onboarding.md
    )
    allowed='^(ci|cd|cd-plan|check|check-app|check-all|check-generated|clean-generated|deploy|diff-generated|render|render-all|vm|k8s|flux|ssh|gc|update|install-hooks)$'
    legacy='just (check-(ci|nix|k8s|yaml|shell|actions|secrets)|deploy-(host|vm|node|all)|vm-(build|provision|start|stop|restart|destroy|cleanup|sync|status)|k8s-(deploy|reset-deploy|bootstrap|clean|verify)|flux-(bootstrap|status|reconcile)|status|net|build)\b'

    if rg -n "$legacy" "${docs[@]}"; then
        echo "Docs still reference legacy just recipes." >&2
        exit 1
    fi

    mapfile -t recipes < <(rg --only-matching --no-filename '\bjust[[:space:]]+[A-Za-z0-9_-]+' "${docs[@]}" | awk '{print $2}' | sort -u)
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
_deploy_host:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r 'join(",")')
    just _colmena apply --on "$targets" --verbose

[private]
_deploy_host_plan:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r 'join(",")')
    echo "Target: hosts ($targets)"
    just _colmena apply dry-activate --no-keys --on "$targets" --verbose

[private]
_deploy_vm:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r 'join(",")')
    just _colmena apply --on "$targets" --verbose

[private]
_deploy_vm_plan:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r 'join(",")')
    echo "Target: vms ($targets)"
    just _colmena apply dry-activate --no-keys --on "$targets" --verbose

[private]
_deploy_nodes +nodes:
    just _colmena apply --on "$(echo "{{ nodes }}" | tr ' ' ',')" --verbose

[private]
_deploy_nodes_plan +nodes:
    #!/usr/bin/env bash
    targets="$(echo "{{ nodes }}" | tr ' ' ',')"
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
    master_ip=$(just _master_ip)
    ssh -F {{ ssh-config }} "$master_ip" "flux get all"

[private]
_flux_reconcile:
    #!/usr/bin/env bash
    master_ip=$(just _master_ip)
    ssh -F {{ ssh-config }} "$master_ip" "flux reconcile source git flux-system && flux reconcile kustomization flux-system"
