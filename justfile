# Tony's Homelab - Justfile
# Development and Production deployment recipes
# Variables dynamically evaluated from Nix constants
# Single source of truth: lib/homelab-constants.nix and flake.nix

ssh_public_key := `if [ -f secrets/ssh-public-key.txt ]; then cat secrets/ssh-public-key.txt; else echo "Error: Missing secrets/ssh-public-key.txt" >&2; exit 1; fi`

# SSH target: Auto-detect from ~/.ssh/config by matching WAN IP

vm_order := `nix eval --impure --raw --expr 'let constants = (builtins.getFlake (toString ./.)).homelabConstants; in builtins.concatStringsSep " " constants.vmOrder' || { echo "Error: Failed to read vmOrder from flake" >&2; exit 1; }`
microvm_list := `nix eval --impure --raw --expr 'let constants = (builtins.getFlake (toString ./.)).homelabConstants; in builtins.concatStringsSep " " constants.microvmList' || { echo "Error: Failed to read microvmList from flake" >&2; exit 1; }`
vm_tag_list := `nix eval --impure --raw --expr 'let constants = (builtins.getFlake (toString ./.)).homelabConstants; in builtins.concatStringsSep " " constants.vmTagList' || { echo "Error: Failed to read vmTagList from flake" >&2; exit 1; }`
target := ```

  wan_ip=$(nix eval --raw .#homelabConstants.networks.wan.host 2>/dev/null)
  if [ -z "$wan_ip" ]; then
    echo "Error: Failed to read WAN IP from flake" >&2
    exit 1
  fi

  # Parse ~/.ssh/config to find Host with matching HostName
  ssh_host=$(awk -v ip="$wan_ip" '
    /^Host / { host=$2 }
    /^[[:space:]]*HostName[[:space:]]/ {
      if ($2 == ip && host != "*") {
        print host
        exit
      }
    }
  ' ~/.ssh/config)

  if [ -z "$ssh_host" ]; then
    echo "" >&2
    echo "============================================" >&2
    echo "ERROR: SSH config not found for homelab server" >&2
    echo "============================================" >&2
    echo "" >&2
    echo "Please add this configuration to ~/.ssh/config:" >&2
    echo "" >&2
    echo "Host homelab" >&2
    echo "  HostName $wan_ip" >&2
    echo "  User username" >&2
    echo "  IdentityFile ~/.ssh/your-key.pem" >&2
    echo "  ServerAliveInterval 60" >&2
    echo "  ServerAliveCountMax 3" >&2
    echo "" >&2
    exit 1
  fi

  echo "$ssh_host"
```

# VM IP addresses from constants

vault_ip := `nix eval --impure --raw .#homelabConstants.vms.vault.ip || { echo "Error: Failed to read vault IP" >&2; exit 1; }`
jenkins_ip := `nix eval --impure --raw .#homelabConstants.vms.jenkins.ip || { echo "Error: Failed to read jenkins IP" >&2; exit 1; }`
registry_ip := `nix eval --impure --raw .#homelabConstants.vms.registry.ip || { echo "Error: Failed to read registry IP" >&2; exit 1; }`
k8s_master := `nix eval --impure --raw .#homelabConstants.k8s.master || { echo "Error: Failed to read k8s master host" >&2; exit 1; }`
k8s_worker_list := `nix eval --impure --raw --expr 'let constants = (builtins.getFlake (toString ./.)).homelabConstants; in builtins.concatStringsSep " " constants.k8s.workerOrder' || { echo "Error: Failed to read k8s worker list" >&2; exit 1; }`
k8s_master_ip := `nix eval --impure --raw '.#homelabConstants.vms."k8s-master".ip' || { echo "Error: Failed to read k8s master IP" >&2; exit 1; }`
k8s_worker1_ip := `nix eval --impure --raw '.#homelabConstants.vms."k8s-worker-1".ip' || { echo "Error: Failed to read k8s worker-1 IP" >&2; exit 1; }`
k8s_worker2_ip := `nix eval --impure --raw '.#homelabConstants.vms."k8s-worker-2".ip' || { echo "Error: Failed to read k8s worker-2 IP" >&2; exit 1; }`

# =============================================================================
# Development Commands (Local Testing)
# =============================================================================

# Check flake configuration for errors
check:
    nix flake check --impure --all-systems

# Build configuration locally (dry-run)
# Usage: just build
# Usage: just build homelab
# Usage: just build jenkins
# Usage: just build vm-jenkins

# Usage: just build k8s
_resolve_target target:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ target }}" = "homelab" ]; then
        echo "@homelab"
    elif [ "{{ target }}" = "vms" ]; then
        echo "@"$(echo "{{ vm_tag_list }}" | tr ' ' ',')
    elif [ "{{ target }}" = "k8s" ]; then
        echo "@k8s"
    else
        echo "{{ target }}"
    fi

_colmena cmd target extra_flags="" microvm_targets="":
    #!/usr/bin/env bash
    set -euo pipefail
    on_target=$(just _resolve_target {{ target }})
    MICROVM_TARGETS="{{ microvm_targets }}" SSH_PUB_KEY="{{ ssh_public_key }}" nix run --impure .#colmena -- {{ cmd }} {{ extra_flags }} --on "$on_target"

_ssh cmd:
    ssh {{ target }} "{{ cmd }}"

_microvm_action action vm:
    just _ssh "sudo systemctl {{ action }} microvm@{{ vm }}"

_microvm_status:
    just _ssh "systemctl list-units 'microvm@*' --no-pager"

_microvm_bulk_action action:
    #!/usr/bin/env bash
    set -euo pipefail
    VMS="{{ microvm_list }}"
    declare -A PIDS=()
    for vm in $VMS; do
        echo "🔄 Sending {{ action }} signal to microvm@$vm..."
        ssh {{ target }} "sudo systemctl {{ action }} microvm@$vm" &
        PIDS[$vm]=$!
    done

    FAILED_VMS=()
    for vm in "${!PIDS[@]}"; do
        if ! wait "${PIDS[$vm]}"; then
            FAILED_VMS+=("$vm")
        fi
    done

    if [ ${#FAILED_VMS[@]} -gt 0 ]; then
        echo "❌ Failed to {{ action }}: ${FAILED_VMS[*]}" >&2
        exit 1
    fi

_microvm_wait_running:
    #!/usr/bin/env bash
    set -euo pipefail
    MAX_RETRIES=15
    for ((i=1; i<=MAX_RETRIES; i++)); do
        FAILED_COUNT=$(ssh {{ target }} "systemctl list-units 'microvm@*' --no-legend --no-pager | awk '{print $1}' | xargs -I {} systemctl show -p SubState --value {} | grep -vc '^running$' || true")
        if [ "$FAILED_COUNT" -eq 0 ]; then
            echo "✅ All VMs are now running."
            exit 0
        fi
        if [ "$i" -eq "$MAX_RETRIES" ]; then
            echo "⚠️  Some VMs are taking too long or failed to start."
            exit 1
        fi
        echo "... waiting ($i/$MAX_RETRIES)"
        sleep 3
    done

_vm_ssh ip:
    ssh -J {{ target }} root@{{ ip }}

_vm_ip vm:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ vm }}" in
        vault) echo "{{ vault_ip }}" ;;
        jenkins) echo "{{ jenkins_ip }}" ;;
        registry) echo "{{ registry_ip }}" ;;
        k8s-master) echo "{{ k8s_master_ip }}" ;;
        k8s-worker-1|k8s-worker1) echo "{{ k8s_worker1_ip }}" ;;
        k8s-worker-2|k8s-worker2) echo "{{ k8s_worker2_ip }}" ;;
        *) echo "Unknown VM: {{ vm }}" >&2; exit 1 ;;
    esac

build target="all":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ target }}" = "all" ]; then
        just _colmena build homelab "" "all"
        exit 0
    fi
    just _colmena build homelab "" "{{ target }}"

# Update flake inputs
update:
    nix flake update

# Show current infrastructure values
show-config:
    @echo "=== SSH Connection ==="
    @echo "Detected Host: {{ target }}"
    @echo "WAN IP:        $(nix eval --raw .#homelabConstants.networks.wan.host)"
    @echo "Source:        ~/.ssh/config (auto-detected)"
    @echo ""
    @echo "=== Network Configuration ==="
    @echo "WAN Network:   $(nix eval --raw .#homelabConstants.networks.wan.network)"
    @echo "WAN Gateway:   $(nix eval --raw .#homelabConstants.networks.wan.gateway)"
    @echo ""
    @echo "=== VM IP Addresses ==="
    @echo "Vault (VLAN 10):        {{ vault_ip }}"
    @echo "Jenkins (VLAN 10):      {{ jenkins_ip }}"
    @echo "Registry (VLAN 20):     {{ registry_ip }}"
    @echo "K8s Master (VLAN 20):   {{ k8s_master_ip }}"
    @echo "K8s Worker-1 (VLAN 20): {{ k8s_worker1_ip }}"
    @echo "K8s Worker-2 (VLAN 20): {{ k8s_worker2_ip }}"

# =============================================================================
# Production Deployment
# =============================================================================
# Deploy by target (homelab or vm name)
# Usage: just deploy
# Usage: just deploy homelab
# Usage: just deploy vault
# Available node names: vault, jenkins, registry, k8s-master, k8s-worker-1, k8s-worker-2

# Targets: homelab, vm name
deploy target="all":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ target }}" = "all" ]; then
        just _colmena apply homelab "--verbose --impure" "all"
        exit 0
    fi
    if [ "{{ target }}" = "homelab" ]; then
        just _colmena apply homelab "--verbose --impure" "none"
        exit 0
    fi
    just _colmena apply homelab "--verbose --impure" "{{ target }}"

# =============================================================================
# MicroVM Management
# =============================================================================

# Show all VMs status
vm-status:
    just _microvm_status

# Start a specific VM (or all)
vm-start vm:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ vm }}" = "all" ]; then
        echo "🟢 Starting all MicroVMs on {{ target }}..."
        just _microvm_bulk_action start
        echo "⏳ Waiting for VMs to stabilize..."
        just _microvm_wait_running
        just vm-status
        exit 0
    fi
    just _microvm_action start {{ vm }}

# Stop a specific VM (or all)
vm-stop vm:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ vm }}" = "all" ]; then
        echo "🛑 Stopping all MicroVMs..."
        just _microvm_bulk_action stop
        echo "⏳ Waiting for VMs to stop..."
        sleep 3
        echo "✓ All VMs stopped"
        just vm-status
        exit 0
    fi
    just _microvm_action stop {{ vm }}

# Stop all VMs
vm-stop-all:
    just vm-stop all

# Restart a specific VM (or all)
vm-restart vm:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ vm }}" = "all" ]; then
        echo "🟢 Restarting all MicroVMs on {{ target }}..."
        just _microvm_bulk_action restart
        echo "⏳ Waiting for VMs to stabilize..."
        just _microvm_wait_running
        just vm-status
        exit 0
    fi
    just _microvm_action restart {{ vm }}

# View VM logs (follow mode)
vm-logs vm:
    just _ssh "journalctl -u microvm@{{ vm }} -f"

# Access VM console (Ctrl-A, X to exit)
vm-console vm:
    ssh {{ target }} -t "sudo microvm console {{ vm }}"

# SSH into a VM by name
vm-ssh vm:
    just _vm_ssh $(just _vm_ip {{ vm }})

# Ping all VMs to check connectivity
vm-ping:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Checking VM connectivity..."
    echo ""
    echo "VLAN 10 (Management):"
    ssh {{ target }} "ping -c 2 {{ vault_ip }} && echo '✓ Vault ({{ vault_ip }})' || echo '✗ Vault ({{ vault_ip }})'" &
    PID_VAULT=$!
    ssh {{ target }} "ping -c 2 {{ jenkins_ip }} && echo '✓ Jenkins ({{ jenkins_ip }})' || echo '✗ Jenkins ({{ jenkins_ip }})'" &
    PID_JENKINS=$!
    wait "$PID_VAULT" "$PID_JENKINS"
    echo ""
    echo "VLAN 20 (Services):"
    ssh {{ target }} "ping -c 2 {{ registry_ip }} && echo '✓ Registry ({{ registry_ip }})' || echo '✗ Registry ({{ registry_ip }})'" &
    PID_REGISTRY=$!
    ssh {{ target }} "ping -c 2 {{ k8s_master_ip }} && echo '✓ K8s Master ({{ k8s_master_ip }})' || echo '✗ K8s Master ({{ k8s_master_ip }})'" &
    PID_K8S_MASTER=$!
    ssh {{ target }} "ping -c 2 {{ k8s_worker1_ip }} && echo '✓ K8s Worker-1 ({{ k8s_worker1_ip }})' || echo '✗ K8s Worker-1 ({{ k8s_worker1_ip }})'" &
    PID_K8S_WORKER1=$!
    ssh {{ target }} "ping -c 2 {{ k8s_worker2_ip }} && echo '✓ K8s Worker-2 ({{ k8s_worker2_ip }})' || echo '✗ K8s Worker-2 ({{ k8s_worker2_ip }})'" &
    PID_K8S_WORKER2=$!
    wait "$PID_REGISTRY" "$PID_K8S_MASTER" "$PID_K8S_WORKER1" "$PID_K8S_WORKER2"

# =============================================================================
# Initial Setup (One-time operations)
# =============================================================================

# Create VM storage directories on homelab
vm-setup-storage:
    #!/usr/bin/env bash
    ssh {{ target }} << 'EOF'
        sudo mkdir -p /var/lib/microvms/vault/data
        sudo mkdir -p /var/lib/microvms/jenkins/home
        sudo mkdir -p /var/lib/microvms/registry/data
        sudo mkdir -p /var/lib/microvms/k8s-master/etcd
        sudo chown -R root:kvm /var/lib/microvms
        sudo chmod -R 0755 /var/lib/microvms
        echo "✓ MicroVM storage directories created"
        ls -la /var/lib/microvms/
    EOF

# Full initial deployment (setup + deploy + start VMs)
init:
    @echo "🚀 Starting full homelab deployment..."
    @just setup-ssh-key
    @just vm-setup-storage
    @just deploy
    @echo "⏳ Waiting for deployment to complete..."
    @sleep 5
    @just vm-status
    @just vm-ping

# =============================================================================
# Network Debugging & Validation
# =============================================================================

# Show complete network topology and configuration
net-show:
    #!/usr/bin/env bash
    echo "🌐 Network Topology Overview"
    echo ""
    echo "=== IP Addresses ==="
    ssh {{ target }} "ip -c addr show"
    echo ""
    echo "=== Routing Table ==="
    ssh {{ target }} "ip -c route show"
    echo ""
    echo "=== Bridge Configuration ==="
    ssh {{ target }} "ip -d link show vmbr0"
    echo ""
    echo "=== VLAN Interfaces ==="
    ssh {{ target }} "ip -d link show type vlan"

# Check VLAN bridge filtering status
net-check-vlan:
    #!/usr/bin/env bash
    echo "🔍 VLAN Bridge Filtering Status"
    echo ""
    echo "=== Bridge VLAN Table (vmbr0) ==="
    ssh {{ target }} "sudo bridge vlan show dev vmbr0"
    echo ""
    echo "=== VLAN 10 (Management) Ports ==="
    ssh {{ target }} "sudo bridge vlan show | grep -E '(vm-vault|vm-jenkins|vlan10)'"
    echo ""
    echo "=== VLAN 20 (Services) Ports ==="
    ssh {{ target }} "sudo bridge vlan show | grep -E '(vm-registry|vm-k8s-master|vm-k8s-worker|vlan20)'"

# Verify bridge membership and state
net-check-bridge:
    #!/usr/bin/env bash
    echo "🌉 Bridge Membership & State"
    echo ""
    echo "=== Bridge vmbr0 Members ==="
    ssh {{ target }} "bridge link show | grep vmbr0"
    echo ""
    echo "=== Bridge FDB (Forwarding Database) ==="
    ssh {{ target }} "sudo bridge fdb show br vmbr0"

# Check systemd-networkd status and configuration
net-check-networkd:
    #!/usr/bin/env bash
    echo "⚙️  systemd-networkd Status"
    echo ""
    echo "=== Service Status ==="
    ssh {{ target }} "systemctl status systemd-networkd --no-pager"
    echo ""
    echo "=== Network State ==="
    ssh {{ target }} "networkctl status"
    echo ""
    echo "=== VLAN Interface States ==="
    ssh {{ target }} "networkctl status vlan10 vlan20"

# Check ARP tables (Layer 2 connectivity)
net-check-arp:
    #!/usr/bin/env bash
    echo "📡 ARP Table Analysis"
    echo ""
    echo "=== Host ARP Table ==="
    ssh {{ target }} "ip neigh show"
    echo ""
    echo "=== Management VLAN ==="
    ssh {{ target }} "ip neigh show dev vlan10"
    echo ""  
    echo "=== Services VLAN ===" 
    ssh {{ target }} "ip neigh show dev vlan20"

# Comprehensive network diagnostic
net-diagnose:
    #!/usr/bin/env bash
    echo "🏥 Comprehensive Network Diagnostic"
    echo ""
    echo "=================================================="
    echo "1. VLAN Bridge Configuration"
    echo "=================================================="
    just net-check-vlan
    echo ""
    echo "=================================================="
    echo "2. Bridge Membership"
    echo "=================================================="
    just net-check-bridge
    echo ""
    echo "=================================================="
    echo "3. systemd-networkd Status"
    echo "=================================================="
    just net-check-networkd
    echo ""
    echo "=================================================="
    echo "4. ARP Tables (Layer 2)"
    echo "=================================================="
    just net-check-arp
    echo ""
    echo "=================================================="
    echo "5. Connectivity Tests"
    echo "=================================================="
    just net-test-homelab-to-vm
    echo ""
    echo "=================================================="
    echo "6. Packet Forwarding & NAT"
    echo "=================================================="
    ssh {{ target }} "sudo sysctl net.ipv4.ip_forward"
    ssh {{ target }} "sudo iptables -t nat -L -n -v | head -20"

# Reset VM network interface (restart microvm)
net-reset-vm vm:
    #!/usr/bin/env bash
    echo "🔄 Resetting network for VM: {{ vm }}"
    just vm-restart {{ vm }}
    echo "⏳ Waiting for VM to restart..."
    sleep 5
    echo "✓ VM restarted"

# Reset all network interfaces (dangerous - use with caution)
net-reset-all:
    #!/usr/bin/env bash
    echo "⚠️  WARNING: This will restart systemd-networkd on the homelab!"
    echo "This may cause temporary network disruption."
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled"
        exit 1
    fi
    echo "🔄 Restarting systemd-networkd..."
    ssh {{ target }} "sudo systemctl restart systemd-networkd"
    echo "⏳ Waiting for network to stabilize..."
    sleep 5
    echo "✓ Network service restarted"
