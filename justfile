# Tony's Homelab - High Efficiency Justfile (Self-contained)
# Single source of truth for all operations

# Data Extraction (SSOT)
_nix_eval expr:
    @nix eval --impure --raw --expr 'let d = import ./data; in {{ expr }}'

vms := `nix eval --impure --raw --expr 'let d = import ./data; in builtins.concatStringsSep " " d.vms.order'`
target := ```
  lan_ip=$(nix eval --impure --raw --expr 'let d = import ./data; in d.network.wan.host')
  ts_ip=$(nix eval --impure --raw --expr 'let d = import ./data; in d.network.tailscale.host')
  user=$(nix eval --impure --raw --expr 'let d = import ./data; in d.hosts.definitions.homelab.deployment.targetUser')

  # 1) LAN: direct SSH (fastest)
  if [ -n "$lan_ip" ] && ssh -o ConnectTimeout=2 -o BatchMode=yes "${user}@${lan_ip}" true 2>/dev/null; then
    echo "$lan_ip"
    exit 0
  fi

  # 2) Tailscale IP fallback (works from anywhere)
  if [ -n "$ts_ip" ] && ssh -o ConnectTimeout=3 -o BatchMode=yes "${user}@${ts_ip}" true 2>/dev/null; then
    echo "$ts_ip"
    exit 0
  fi

  echo "Error: Cannot reach homelab via LAN ($lan_ip) or Tailscale ($ts_ip)" >&2
  exit 1
```
deploy_user := `nix eval --impure --raw --expr 'let d = import ./data; in d.hosts.definitions.homelab.deployment.targetUser'`
ssh_pub_key := `if [ -f secrets/ssh-public-key.txt ]; then cat secrets/ssh-public-key.txt; else echo "Error" >&2; exit 1; fi`

# Internal Helpers
_ssh cmd:
    @ssh {{ deploy_user }}@{{ target }} "{{ cmd }}"

# Deployment Helper
_run cmd on="" targets="all":
    #!/usr/bin/env bash
    set -euo pipefail
    ON="{{ on }}"
    if [ -z "$ON" ]; then ON="homelab"; fi
    DEPLOY_TARGET="{{ target }}" MICROVM_TARGETS="{{ targets }}" SSH_PUB_KEY="{{ ssh_pub_key }}" \
        nix run --impure .#colmena -- {{ cmd }} --on "$ON" --impure --show-trace

# -----------------------------------------------------------------------------
# 1. Deployment & Sync
# -----------------------------------------------------------------------------

# Sync entire infrastructure (Server + All VMs)
up:
    @just _run apply
    @echo "✅ Infrastructure deployed."

# --- [ Kubernetes Cluster Management ] ---

# Full Kubernetes deployment (Clean & Re-install)
k8s-deploy:
    @echo "🚀 Starting full Kubernetes deployment (Clean + Bootstrap)..."
    @just k8s-clean
    @just k8s-bootstrap

# Install Kubernetes cluster on a clean environment
k8s-bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    just wait-for-vms
    key_file="$(ssh -G {{ target }} | awk '/^identityfile / {print $2; exit}')"
    if [[ "$key_file" == "~/"* ]]; then
      key_file="$HOME/${key_file#\~/}"
    fi
    # Fallback to id_ed25519 if detected key doesn't exist
    if [ ! -f "$key_file" ] && [ -f "$HOME/.ssh/id_ed25519" ]; then
      key_file="$HOME/.ssh/id_ed25519"
    fi
    [ -f "$key_file" ] || { echo "❌ SSH private key not found: $key_file"; exit 1; }
    # Run ONLY setup tasks
    DEPLOY_TARGET="{{ target }}" SSH_KEY_FILE="$key_file" ansible-playbook --private-key "$key_file" -i ansible/inventory.py ansible/site.yml --tags bootstrap

# Wipe all Kubernetes state and data from all nodes
k8s-clean:
    #!/usr/bin/env bash
    set -euo pipefail
    just wait-for-vms
    key_file="$(ssh -G {{ target }} | awk '/^identityfile / {print $2; exit}')"
    if [[ "$key_file" == "~/"* ]]; then
      key_file="$HOME/${key_file#\~/}"
    fi
    # Fallback to id_ed25519 if detected key doesn't exist
    if [ ! -f "$key_file" ] && [ -f "$HOME/.ssh/id_ed25519" ]; then
      key_file="$HOME/.ssh/id_ed25519"
    fi
    [ -f "$key_file" ] || { echo "❌ SSH private key not found: $key_file"; exit 1; }
    # Run ONLY cleanup tasks
    DEPLOY_TARGET="{{ target }}" SSH_KEY_FILE="$key_file" ansible-playbook --private-key "$key_file" -i ansible/inventory.py ansible/site.yml --tags cleanup -e reset_cluster=true

# Wait for all VM SSH ports to be open
wait-for-vms:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Checking VM availability..."
    IPS=$(./ansible/inventory.py | jq -r '._meta.hostvars[].ansible_host')
    JUMP_HOST="{{ target }}"
    JUMP_USER="{{ deploy_user }}"
    MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-300}"
    for ip in $IPS; do
        echo -n "  Waiting for $ip:22..."
        start_ts=$(date +%s)
        until ssh "$JUMP_USER@$JUMP_HOST" "nc -zvw1 '$ip' 22" &>/dev/null; do
            now_ts=$(date +%s)
            if [ $((now_ts - start_ts)) -ge "$MAX_WAIT_SECONDS" ]; then
                echo ""
                echo "❌ Timeout waiting for $ip:22 after ${MAX_WAIT_SECONDS}s"
                echo "   Check: sudo systemctl status microvm@<node> microvm-virtiofsd@<node> on $JUMP_HOST"
                exit 1
            fi
            echo -n "."
            sleep 2
        done
        echo " OK"
    done
    echo "🚀 All VMs are reachable via SSH."

# Sync specific target (e.g., just sync k8s-master-1)
sync name:
    @just _run apply --on {{ name }} --targets {{ name }}

# -----------------------------------------------------------------------------
# 2. Management & Control
# -----------------------------------------------------------------------------

# List all running units (VMs + Network)
ls:
    @echo "--- MicroVM Units ---"
    @just _ssh "systemctl list-units 'microvm@*' --no-pager"
    @echo ""
    @echo "--- Network Status ---"
    @just _ssh "networkctl list"

# Control VM lifecycle (e.g., just vm stop k8s-worker-1 / just vm start all)
vm action name="all":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ name }}" = "all" ]; then
        echo "🔄 Action '{{ action }}' on ALL MicroVMs..."
        for vm in {{ vms }}; do
            echo "  {{ action }} microvm@$vm..."
            ssh {{ deploy_user }}@{{ target }} "sudo systemctl {{ action }} microvm@$vm" &
        done
        wait
    else
        echo "🚀 {{ action }} microvm@{{ name }}..."
        ssh {{ deploy_user }}@{{ target }} "sudo systemctl {{ action }} microvm@{{ name }}"
    fi

# Access VM console (Ctrl-A, X to exit)
console name:
    @ssh {{ deploy_user }}@{{ target }} -t "sudo microvm console {{ name }}"

# -----------------------------------------------------------------------------
# 3. Maintenance & Debug
# -----------------------------------------------------------------------------

# Deep network & system diagnostic
debug:
    #!/usr/bin/env bash
    set -euo pipefail
    _remote() { ssh {{ deploy_user }}@{{ target }} "$@"; }
    echo "🌐 [1/4] Network Topology" && _remote "ip -c addr show && ip -c route show"
    echo ""
    echo "🔍 [2/4] VLAN Bridge" && _remote "sudo bridge vlan show dev vmbr0"
    echo ""
    echo "🌉 [3/4] Bridge FDB" && _remote "sudo bridge fdb show br vmbr0"
    echo ""
    echo "⚙️  [4/4] networkd Status" && _remote "networkctl status vlan10 vlan20"

check:
    nix flake check --impure --all-systems

update:
    nix flake update
