set shell := ["bash", "-euo", "pipefail", "-c"]

topology := "./network/topology.nix"

# 동적 SSH config (topology.nix + tailscale → .cache/ssh-config)
# justfile 실행 시 1회 평가, 모든 recipe에서 재사용
ssh-config := ```
  mkdir -p .cache
  config_file=".cache/ssh-config"
  hosts_json=$(nix eval --impure --json --expr '(import ./network/topology.nix).hosts')
  ts_json=$(tailscale status --json 2>/dev/null || echo '{"Peer":[]}')
  {
    for host in $(echo "$hosts_json" | jq -r 'keys[]'); do
      user=$(echo "$hosts_json" | jq -r ".\"$host\".user")
      ts_ip=$(echo "$ts_json" | jq -r ".Peer[] | select(.HostName == \"$host\" or (.DNSName | startswith(\"$host.\"))) | .TailscaleIPs[0] // empty" 2>/dev/null || echo "")
      if [ -z "$ts_ip" ]; then
        ts_ip=$(echo "$hosts_json" | jq -r ".\"$host\".ip")
      fi
      echo "Host $host"
      echo "    HostName $ts_ip"
      echo "    User $user"
      echo "    StrictHostKeyChecking no"
      echo ""
    done
    first_host=$(echo "$hosts_json" | jq -r 'keys[0]')
    echo "Host 10.0.20.* k8s-master-* k8s-worker-*"
    echo "    User root"
    echo "    ProxyJump $first_host"
    echo "    StrictHostKeyChecking no"
    echo "    UserKnownHostsFile /dev/null"
  } > "$config_file"
  echo "$config_file"
```

# =============================================================================
# Private: 인프라 헬퍼
# =============================================================================

# Colmena wrapper (SSH_CONFIG_FILE로 동적 SSH config 주입)
[private]
_colmena +args:
    SSH_CONFIG_FILE={{ ssh-config }} nix run --impure .#colmena -- {{ args }}

# SSH to any node (ssh-config이 host/VM 라우팅 자동 처리)
[private]
_ssh node +cmd:
    ssh -F {{ ssh-config }} {{ node }} {{ cmd }}

# =============================================================================
# Deploy (Colmena)
# =============================================================================

# Deploy all (host first → VMs)
deploy-all: deploy-host deploy-vms

# Deploy physical host(s)
deploy-host:
    #!/usr/bin/env bash
    set -euo pipefail
    hosts=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r 'join(",")')
    just _safe-deploy "$hosts"

# Deploy all VMs
deploy-vms:
    #!/usr/bin/env bash
    set -euo pipefail
    vms=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r 'join(",")')
    just _safe-deploy "$vms"

# Deploy specific node(s): just deploy k8s-master-1 k8s-worker-1
deploy +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(echo "{{ nodes }}" | tr ' ' ',')
    just _safe-deploy "$targets"

# Build only (no apply)
build *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{ nodes }}" ]; then
        just _colmena build --verbose
    else
        targets=$(echo "{{ nodes }}" | tr ' ' ',')
        just _colmena build --on "$targets" --verbose
    fi

# Eval check → Colmena apply
[private]
_safe-deploy +nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Eval check: {{ nodes }} ==="
    for node in $(echo "{{ nodes }}" | tr ',' ' '); do
        nix eval --impure --expr "(builtins.getFlake \"git+file://$PWD\").colmenaHive.nodes.$node.config.system.build.toplevel" >/dev/null
        echo "  $node: OK"
    done
    echo ""
    echo "=== Applying: {{ nodes }} ==="
    just _colmena apply --on "{{ nodes }}" --verbose

# =============================================================================
# VM Image Provisioning
# =============================================================================

# VM QCOW2 이미지 빌드 (물리 호스트에서 원격 빌드)
build-images *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    remote_dir="/tmp/homelab-build"

    if [ -z "{{ vms }}" ]; then
        targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r '.[]')
    else
        targets="{{ vms }}"
    fi

    echo "=== Syncing repo to $host ==="
    ssh -F {{ ssh-config }} -o ConnectTimeout=10 "$host" "rm -rf $remote_dir"
    rsync -az --filter=':- .gitignore' --exclude='.git' --exclude='result*' \
        -e "ssh -F {{ ssh-config }} -o ConnectTimeout=10" . "$host:$remote_dir/"

    for vm in $targets; do
        echo "=== Building image: $vm ==="
        ssh -F {{ ssh-config }} "$host" "cd $remote_dir && nix build --impure '.#$vm' -o /tmp/image-$vm"
        echo "=== Copying to base images ==="
        ssh -F {{ ssh-config }} "$host" "sudo mkdir -p /var/lib/libvirt/images/base && sudo cp /tmp/image-$vm/*.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
        ssh -F {{ ssh-config }} "$host" "rm -f /tmp/image-$vm"
        echo "  $vm: OK"
    done

    ssh -F {{ ssh-config }} "$host" "rm -rf $remote_dir"
    echo "=== Done. Run 'just provision-vms' to apply. ==="

# VM 프로비저닝 (base 이미지 → 실제 디스크 복사 + VM 재시작)
provision-vms *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    ssh_timeout_s="${PROVISION_SSH_TIMEOUT:-300}"

    if [ -z "{{ vms }}" ]; then
        targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r '.[]')
    else
        targets="{{ vms }}"
    fi

    for vm in $targets; do
        echo "=== Provisioning: $vm ==="
        just _ssh "$host" "sudo virsh destroy $vm 2>/dev/null || true"
        just _ssh "$host" "sudo rm -f /var/lib/libvirt/images/$vm.qcow2"
        just _ssh "$host" "sudo systemctl restart vm-$vm.service"
        echo "  $vm: provisioned"
    done

    echo "=== Waiting for SSH on provisioned VMs... ==="
    for vm in $targets; do
        vm_ip=$(nix eval --impure --raw --expr "(import {{ topology }}).vms.$vm.ip")
        printf "  Waiting for $vm ($vm_ip)..."
        start_ts=$(date +%s)
        while true; do
            if just _ssh "$host" "nc -zvw1 $vm_ip 22" &>/dev/null; then
                echo " OK"
                break
            fi
            elapsed=$(( $(date +%s) - start_ts ))
            if [ "$elapsed" -ge "$ssh_timeout_s" ]; then
                echo " TIMEOUT (${ssh_timeout_s}s)"
                just _ssh "$host" "sudo journalctl -u 'vm-$vm.service' -n 30 --no-pager || true"
                exit 1
            fi
            printf "."
            sleep 2
        done
    done
    echo "=== Done. Run 'just deploy-vms' to apply latest config. ==="

# =============================================================================
# Access & Lifecycle
# =============================================================================

# SSH into any node
ssh node:
    ssh -F {{ ssh-config }} {{ node }}

# VM lifecycle: just vm start|stop|restart [name|all]
vm action name="all":
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    if [ "{{ name }}" = "all" ]; then
        vms=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r '.[]')
    else
        vms="{{ name }}"
    fi
    case "{{ action }}" in
        stop) virsh_cmd="shutdown" ;;
        restart) virsh_cmd="reboot" ;;
        *) virsh_cmd="{{ action }}" ;;
    esac
    for vm in $vms; do
        echo "$virsh_cmd-ing $vm on $host..."
        just _ssh "$host" "sudo virsh $virsh_cmd $vm" &
    done
    wait
    echo "Done."

# =============================================================================
# Status
# =============================================================================

# System health (all hosts + VMs)
status:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in $(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]'); do
        echo "=== Host: $host ==="
        just _ssh "$host" "bash -c 'uptime && echo && df -h / /nix/store 2>/dev/null'" || echo "Unreachable"
        echo ""
    done
    just vm-status

# VM units + SSH connectivity
vm-status:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    echo "=== Libvirt Domains ==="
    just _ssh "$host" "sudo virsh list --all" || true
    echo ""
    echo "=== VM Connectivity ==="
    vms=$(nix eval --impure --json --expr '(import {{ topology }}).vms' | jq -r 'to_entries[] | "\(.key) \(.value.ip)"')
    while IFS=' ' read -r name ip; do
        if just _ssh "$host" "nc -zvw2 $ip 22" &>/dev/null; then
            echo "  $name ($ip): OK"
        else
            echo "  $name ($ip): UNREACHABLE"
        fi
    done <<< "$vms"

# Network: bridge, VLAN, routing
net:
    #!/usr/bin/env bash
    set -euo pipefail
    for host in $(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]'); do
        echo "=== Network: $host ==="
        echo "--- Bridge & VLAN ---"
        just _ssh "$host" "bridge vlan show 2>/dev/null || echo 'N/A'"
        echo "--- Interfaces ---"
        just _ssh "$host" "networkctl list"
        echo "--- Routes ---"
        just _ssh "$host" "ip route"
        echo ""
    done

# Generate topology diagram
topology-diagram:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    remote_dir="/tmp/homelab-topology"
    echo "=== Syncing repo to $host ==="
    ssh -F {{ ssh-config }} "$host" "rm -rf $remote_dir"
    rsync -az --filter=':- .gitignore' --exclude='.git' --exclude='result*' \
        -e "ssh -F {{ ssh-config }}" . "$host:$remote_dir/"
    echo "=== Building topology on $host ==="
    just _ssh "$host" "cd $remote_dir && nix build --impure '.#topology.x86_64-linux.config.output' -o /tmp/topology-result"
    rm -rf result-topology
    mkdir -p result-topology
    scp -F {{ ssh-config }} -r "$host:/tmp/topology-result/*" result-topology/
    just _ssh "$host" "rm -rf $remote_dir /tmp/topology-result"
    echo "=== SVGs generated in ./result-topology/ ==="
    ls result-topology/

# =============================================================================
# Kubernetes
# =============================================================================

# Full lifecycle: clean → bootstrap → verify
k8s-deploy: k8s-clean k8s-bootstrap k8s-verify

# Bootstrap cluster
k8s-bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    target=$(ssh -F {{ ssh-config }} -G "$host" | awk '/^hostname / {print $2; exit}')
    key="$HOME/.ssh/id_ed25519"
    DEPLOY_TARGET="$target" ansible-playbook -i ansible/inventory.py ansible/site.yml \
        --private-key "$key" --tags bootstrap -v

# Reset cluster
k8s-clean:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    target=$(ssh -F {{ ssh-config }} -G "$host" | awk '/^hostname / {print $2; exit}')
    key="$HOME/.ssh/id_ed25519"
    DEPLOY_TARGET="$target" ansible-playbook -i ansible/inventory.py ansible/site.yml \
        --private-key "$key" --tags cleanup -e reset_cluster=true -v

# Cluster health check
k8s-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(nix eval --impure --raw --expr 'builtins.head (builtins.attrNames (import {{ topology }}).hosts)')
    master_ip=$(nix eval --impure --json --expr '(import {{ topology }}).vms' \
        | jq -r 'to_entries[] | select(.key | startswith("k8s-master")) | .value.ip' | head -1)
    api_vip=$(nix eval --impure --raw --expr '(import {{ topology }}).kubernetes.api_vip')

    kc() { just _ssh "$host" "ssh -o StrictHostKeyChecking=no root@$master_ip $*" 2>/dev/null; }

    echo "=== API Health (VIP: $api_vip) ==="
    kc "curl -sk https://$api_vip:6443/healthz" && echo "" || echo "UNHEALTHY"
    echo ""
    echo "=== Nodes ==="
    kc "kubectl get nodes -o wide" || echo "unavailable"
    echo ""
    echo "=== kube-system Pods ==="
    kc "kubectl get pods -n kube-system -o wide" || echo "unavailable"
    echo ""
    echo "=== Cluster Join Summary ==="
    expected=$(nix eval --impure --json --expr 'builtins.length (builtins.attrNames (import {{ topology }}).vms)')
    actual=$(kc "kubectl get nodes --no-headers 2>/dev/null | wc -l" || echo "0")
    echo "Expected: $expected nodes, Actual: $actual nodes"

# =============================================================================
# Maintenance
# =============================================================================

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
        targets=$(nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)' | jq -r '.[]')
    else
        targets="{{ nodes }}"
    fi
    for node in $targets; do
        echo "=== GC: $node ==="
        just _ssh "$node" "sudo nix-collect-garbage -d && sudo nix-store --optimize && sudo journalctl --vacuum-time=1d" || echo "Failed"
    done
