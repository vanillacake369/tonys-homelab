set shell := ["bash", "-euo", "pipefail", "-c"]

topology := "./network/topology.nix"
resolver := "./lib/resolve-node.nix"

# Resolve node → {ip, user, type, parentIp, parentUser}
[private]
resolve node:
    @nix eval --impure --json --expr '(import {{ resolver }} { node = "{{ node }}"; })'

# Comma-separated VM names
[private]
vm-names:
    @nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r 'join(",")'

# Physical host names (space-separated)
[private]
host-names:
    @nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]'

# All node names (space-separated)
[private]
all-names:
    @nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)' | jq -r '.[]'

# SSH to a resolved node (physical: direct, VM: ProxyJump)
[private]
node-ssh node +cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    info=$(just resolve {{ node }})
    ip=$(echo "$info" | jq -r '.ip')
    user=$(echo "$info" | jq -r '.user')
    type=$(echo "$info" | jq -r '.type')
    if [ "$type" = "physical" ]; then
        ssh "$user@$ip" {{ cmd }}
    else
        pIp=$(echo "$info" | jq -r '.parentIp')
        pUser=$(echo "$info" | jq -r '.parentUser')
        ssh -J "$pUser@$pIp" "$user@$ip" {{ cmd }}
    fi

[private]
colmena +args:
    nix run --impure .#colmena -- {{ args }}

# Dry-run → confirm → apply
[private]
safe-deploy +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Dry-run: {{ nodes }} ==="
    just colmena apply --on "{{ nodes }}" --verbose build
    echo ""
    read -rp "Apply to [{{ nodes }}]? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    echo "=== Applying: {{ nodes }} ==="
    just colmena apply --on "{{ nodes }}" --verbose

[private]
wait-vms:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Waiting for VM fleet..."
    for host in $(just host-names); do
        info=$(just resolve "$host")
        hIp=$(echo "$info" | jq -r '.ip')
        hUser=$(echo "$info" | jq -r '.user')
        vms=$(nix eval --impure --json --expr '(import {{ topology }}).vms' | jq -r '.[] | .ip')
        for ip in $vms; do
            until ssh "$hUser@$hIp" "nc -zvw1 $ip 22" &>/dev/null; do printf "."; sleep 1; done
            echo " $ip OK"
        done
    done

[private]
ansible tags extra="":
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(just host-names | head -1)
    info=$(just resolve "$host")
    target=$(echo "$info" | jq -r '.ip')
    key=$(ssh -G "$target" | awk '/^identityfile / {print $2; exit}')
    key="${key/#\~/$HOME}"
    [ -f "$key" ] || key="$HOME/.ssh/id_ed25519"
    DEPLOY_TARGET="$target" ansible-playbook -i ansible/inventory.py ansible/site.yml \
        --private-key "$key" --tags {{ tags }} {{ extra }} -v

# -----------------------------------------------------------------------------
# Build & Deploy
# -----------------------------------------------------------------------------

# Deploy all (host first → VMs)
deploy-all: deploy-host deploy-vms

# Deploy physical host(s)
deploy-host:
    #!/usr/bin/env bash
    set -euo pipefail
    hosts=$(just host-names | tr '\n' ',')
    just safe-deploy "${hosts%,}"

# Deploy all VMs
deploy-vms:
    just safe-deploy "$(just vm-names)"

# Deploy specific node(s): just deploy k8s-master-1 k8s-worker-1
deploy +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(echo "{{ nodes }}" | tr ' ' ',')
    just safe-deploy "$targets"

# Build only (no apply)
build *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{ nodes }}" ]; then
        just colmena build --verbose
    else
        targets=$(echo "{{ nodes }}" | tr ' ' ',')
        just colmena build --on "$targets" --verbose
    fi

# -----------------------------------------------------------------------------
# VM Access & Lifecycle
# -----------------------------------------------------------------------------

# SSH into any node (physical or VM)
ssh node:
    #!/usr/bin/env bash
    set -euo pipefail
    info=$(just resolve {{ node }})
    ip=$(echo "$info" | jq -r '.ip')
    user=$(echo "$info" | jq -r '.user')
    type=$(echo "$info" | jq -r '.type')
    if [ "$type" = "physical" ]; then
        ssh "$user@$ip"
    else
        pIp=$(echo "$info" | jq -r '.parentIp')
        pUser=$(echo "$info" | jq -r '.parentUser')
        ssh -J "$pUser@$pIp" "$user@$ip"
    fi

# VM lifecycle: just vm start|stop|restart [name|all]
vm action name="all":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ name }}" = "all" ]; then
        vms=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r '.[]')
    else
        vms="{{ name }}"
    fi
    for host in $(just host-names); do
        for vm in $vms; do
            echo "{{ action }}ing $vm on $host..."
            just node-ssh "$host" "sudo systemctl {{ action }} microvm@$vm" &
        done
    done
    wait
    echo "Done."

# -----------------------------------------------------------------------------
# Examination
# -----------------------------------------------------------------------------

# System health (all hosts + VMs)
status:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in $(just host-names); do
        info=$(just resolve "$host")
        ip=$(echo "$info" | jq -r '.ip')
        echo "=== Host: $host ($ip) ==="
        just node-ssh "$host" "uptime && echo '' && free -h && echo '' && df -h / /nix/store 2>/dev/null" || echo "Unreachable"
        echo ""
    done
    just vm-status

# VM units + SSH connectivity
vm-status:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in $(just host-names); do
        echo "=== MicroVM Units ($host) ==="
        just node-ssh "$host" "systemctl list-units 'microvm@*' --no-pager" || true
    done
    echo ""
    echo "=== VM Connectivity ==="
    vms=$(nix eval --impure --json --expr '(import {{ topology }}).vms' | jq -r 'to_entries[] | "\(.key) \(.value.ip)"')
    host=$(just host-names | head -1)
    while IFS=' ' read -r name ip; do
        if just node-ssh "$host" "nc -zvw2 $ip 22" &>/dev/null; then
            echo "  $name ($ip): OK"
        else
            echo "  $name ($ip): UNREACHABLE"
        fi
    done <<< "$vms"

# Network: bridge, VLAN, routing (all hosts)
net:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in $(just host-names); do
        echo "=== Network: $host ==="
        echo "--- Bridge & VLAN ---"
        just node-ssh "$host" "bridge vlan show 2>/dev/null || echo 'N/A'"
        echo "--- Interfaces ---"
        just node-ssh "$host" "networkctl list"
        echo "--- Routes ---"
        just node-ssh "$host" "ip route"
        echo ""
    done

# Generate topology diagram (requires nix-topology flake input)
topology-diagram:
    nix build --impure .#topology.x86_64-linux.config.output -o result-topology
    @echo "SVGs generated in ./result-topology/"
    @ls result-topology/

# -----------------------------------------------------------------------------
# Kubernetes
# -----------------------------------------------------------------------------

# Full lifecycle: clean → bootstrap → verify
k8s-deploy: k8s-clean k8s-bootstrap k8s-verify

# Bootstrap cluster
k8s-bootstrap: wait-vms
    just ansible bootstrap

# Reset cluster
k8s-clean: wait-vms
    just ansible cleanup "-e reset_cluster=true"

# Comprehensive cluster health check
k8s-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    master_ip=$(nix eval --impure --json --expr '(import {{ topology }}).vms' \
        | jq -r 'to_entries[] | select(.key | startswith("k8s-master")) | .value.ip' | head -1)
    api_vip=$(nix eval --impure --raw --expr '(import {{ topology }}).kubernetes.api_vip')
    host=$(just host-names | head -1)

    # Helper: run kubectl on first master via host
    kc() { just node-ssh "$host" "ssh -o StrictHostKeyChecking=no root@$master_ip $*" 2>/dev/null; }

    echo "=== API Health (VIP: $api_vip) ==="
    kc "curl -sk https://$api_vip:6443/healthz" && echo "" || echo "UNHEALTHY"

    echo ""
    echo "=== Nodes ==="
    kc "kubectl get nodes -o wide" || echo "unavailable"

    echo ""
    echo "=== kube-system Pods ==="
    kc "kubectl get pods -n kube-system -o wide" || echo "unavailable"

    echo ""
    echo "=== etcd Health ==="
    kc "ETCDCTL_API=3 etcdctl \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
        --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
        endpoint health --cluster" || echo "unavailable"

    echo ""
    echo "=== Component Status ==="
    for component in kube-apiserver kube-controller-manager kube-scheduler etcd; do
        echo "--- $component (last 10 lines) ---"
        kc "kubectl logs -n kube-system -l component=$component --tail=10 2>/dev/null" || echo "no logs"
        echo ""
    done

    echo "=== Cilium Status ==="
    kc "kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium -o wide" || echo "unavailable"
    echo ""
    echo "--- Cilium Agent Logs (last 10 lines) ---"
    kc "kubectl -n kube-system logs -l app.kubernetes.io/name=cilium-agent --tail=10 2>/dev/null" || echo "no logs"

    echo ""
    echo "=== Cluster Join Summary ==="
    expected=$(nix eval --impure --json --expr 'builtins.length (builtins.attrNames (import {{ topology }}).vms)')
    actual=$(kc "kubectl get nodes --no-headers 2>/dev/null | wc -l" || echo "0")
    echo "Expected: $expected nodes, Actual: $actual nodes"

# -----------------------------------------------------------------------------
# Maintenance
# -----------------------------------------------------------------------------

# Validate flake
check:
    nix flake check --impure --all-systems

# Update flake inputs
update:
    nix flake update

# Garbage collection (all nodes or specific)
gc *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{ nodes }}" ]; then
        targets=$(just all-names)
    else
        targets="{{ nodes }}"
    fi
    for node in $targets; do
        echo "=== GC: $node ==="
        just node-ssh "$node" "sudo nix-collect-garbage -d && sudo nix-store --optimize && sudo journalctl --vacuum-time=1d" || echo "Failed"
    done
