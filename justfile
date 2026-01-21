# Tony's Homelab - Justfile
# Development and Production deployment recipes
# Variables dynamically evaluated from Nix constants
# Single source of truth: lib/homelab-constants.nix and flake.nix

ssh_public_key := `if [ -f secrets/ssh-public-key.txt ]; then cat secrets/ssh-public-key.txt; else echo ""; fi`

# SSH target: Auto-detect from ~/.ssh/config by matching WAN IP

vm_order := "vault jenkins registry k8s-master k8s-worker-1 k8s-worker-2"

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

vault_ip := `nix eval --impure --raw .#homelabConstants.vms.vault.ip`
jenkins_ip := `nix eval --impure --raw .#homelabConstants.vms.jenkins.ip`
registry_ip := `nix eval --impure --raw .#homelabConstants.vms.registry.ip`
k8s_master_ip := `nix eval --impure --raw '.#homelabConstants.vms."k8s-master".ip'`
k8s_worker1_ip := `nix eval --impure --raw '.#homelabConstants.vms."k8s-worker-1".ip'`
k8s_worker2_ip := `nix eval --impure --raw '.#homelabConstants.vms."k8s-worker-2".ip'`

# =============================================================================
# Development Commands (Local Testing)
# =============================================================================

# Check flake configuration for errors
check:
    nix flake check --impure --all-systems

# Build configuration locally (dry-run)
build:
    SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- build --on homelab

# Build by target (host, vms, or node)
# Usage: just build host
# Usage: just build vms
# Usage: just build k8s-master
# Available node names: vault, jenkins, registry, k8s-master, k8s-worker-1, k8s-worker-2
# Tags: host, vms, k8s
# Targets: @host, @vms, @k8s, or node name
build target:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ target }}" = "host" ]; then
        on_target="@host"
    elif [ "{{ target }}" = "vms" ]; then
        on_target="@vms"
    elif [ "{{ target }}" = "k8s" ]; then
        on_target="@k8s"
    else
        on_target="{{ target }}"
    fi
    SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- build --on "$on_target"

# Build all nodes in order (host -> vm_order)
build-all:
    #!/usr/bin/env bash
    set -euo pipefail
    SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- build --on @host
    for vm in {{ vm_order }}; do
        SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- build --on "$vm"
    done

# Format Nix files
fmt:
    nix fmt

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

# Deploy to homelab server
deploy:
    SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- apply --verbose --impure

# Deploy by target (host, vms, or node)
# Usage: just deploy host
# Usage: just deploy vms
# Usage: just deploy k8s-master
# Available node names: vault, jenkins, registry, k8s-master, k8s-worker-1, k8s-worker-2
# Tags: host, vms, k8s
# Targets: @host, @vms, @k8s, or node name
deploy target:

    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ target }}" = "host" ]; then
        on_target="@host"
    elif [ "{{ target }}" = "vms" ]; then
        on_target="@vms"
    elif [ "{{ target }}" = "k8s" ]; then
        on_target="@k8s"
    else
        on_target="{{ target }}"
    fi
    SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- apply --verbose --impure --on "$on_target"

# Deploy all nodes in order (host -> vm_order)
deploy-all:
    #!/usr/bin/env bash
    set -euo pipefail
    SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- apply --verbose --impure --on @host
    for vm in {{ vm_order }}; do
        SSH_PUB_KEY="{{ ssh_public_key }}" nix run .#colmena -- apply --verbose --impure --on "$vm"
    done

# =============================================================================
# MicroVM Management
# =============================================================================

# Show all VMs status
vm-status:
    ssh {{ target }} "systemctl list-units 'microvm@*' --no-pager"

# Start a specific VM
vm-start vm:
    ssh {{ target }} "sudo systemctl start microvm@{{ vm }}"

# Stop a specific VM
vm-stop vm:
    ssh {{ target }} "sudo systemctl stop microvm@{{ vm }}"

# Stop all VMs
vm-stop-all:
    #!/usr/bin/env bash
    echo "🛑 Stopping all MicroVMs..."
    ssh {{ target }} "sudo systemctl stop 'microvm@*'"
    echo "⏳ Waiting for VMs to stop..."
    sleep 3
    echo "✓ All VMs stopped"
    just vm-status

# Restart a specific VM
vm-restart vm:
    ssh {{ target }} "sudo systemctl restart microvm@{{ vm }}"    

# Restart all VMs and wait for them to be active
vm-restart-all:
    #!/usr/bin/env bash
    set -e
    # 쉼표 없이 공백으로 구분된 VM 리스트
    VMS="vault jenkins registry k8s-master k8s-worker-1 k8s-worker-2"
    echo "🟢 Restarting all MicroVMs on {{ target }}..."
    # 1. 모든 서비스를 동시에 재시작 명령 (systemd가 병렬로 처리함)
    for vm in $VMS; do
        echo "🔄 Sending restart signal to microvm@$vm..."
        ssh {{ target }} "sudo systemctl restart microvm@$vm" &
    done
    wait 
    echo "⏳ Waiting for VMs to stabilize..."
    # 2. 상태 확인 루프
    # running 상태가 아닌 유닛 개수 체크
    # microvm@ 뒤에 이름이 붙은 서비스들 중 running이 아닌 것을 찾음
    MAX_RETRIES=15
    for ((i=1; i<=MAX_RETRIES; i++)); do
        FAILED_COUNT=$(ssh {{ target }} "systemctl list-units 'microvm@*' --no-legend | grep -v 'running' | wc -l || true")
        if [ "$FAILED_COUNT" -eq 0 ]; then
            echo "✅ All VMs are now running perfectly."
            break
        fi
        if [ "$i" -eq "$MAX_RETRIES" ]; then
            echo "⚠️  Some VMs are taking too long or failed to start."
            just vm-status
            exit 1
        fi
        echo "... waiting ($i/$MAX_RETRIES)"
        sleep 3
    done
    just vm-status

# View VM logs (follow mode)
vm-logs vm:
    ssh {{ target }} "journalctl -u microvm@{{ vm }} -f"

# Access VM console (Ctrl-A, X to exit)
vm-console vm:
    ssh {{ target }} -t "sudo microvm console {{ vm }}"

# SSH into a VM by name
vm-ssh-vault:
    ssh -J {{ target }} root@{{ vault_ip }}

vm-ssh-jenkins:
    ssh -J {{ target }} root@{{ jenkins_ip }}

vm-ssh-registry:
    ssh -J {{ target }} root@{{ registry_ip }}

vm-ssh-k8s-master:
    ssh -J {{ target }} root@{{ k8s_master_ip }}

vm-ssh-k8s-worker1:
    ssh -J {{ target }} root@{{ k8s_worker1_ip }}

vm-ssh-k8s-worker2:
    ssh -J {{ target }} root@{{ k8s_worker2_ip }}

# Ping all VMs to check connectivity
vm-ping:
    #!/usr/bin/env bash
    echo "🔍 Checking VM connectivity..."
    echo ""
    echo "VLAN 10 (Management):"
    ssh {{ target }} "ping -c 2 {{ vault_ip }} && echo '✓ Vault ({{ vault_ip }})' || echo '✗ Vault ({{ vault_ip }})'"
    ssh {{ target }} "ping -c 2 {{ jenkins_ip }} && echo '✓ Jenkins ({{ jenkins_ip }})' || echo '✗ Jenkins ({{ jenkins_ip }})'"
    echo ""
    echo "VLAN 20 (Services):"
    ssh {{ target }} "ping -c 2 {{ registry_ip }} && echo '✓ Registry ({{ registry_ip }})' || echo '✗ Registry ({{ registry_ip }})'"
    ssh {{ target }} "ping -c 2 {{ k8s_master_ip }} && echo '✓ K8s Master ({{ k8s_master_ip }})' || echo '✗ K8s Master ({{ k8s_master_ip }})'"
    ssh {{ target }} "ping -c 2 {{ k8s_worker1_ip }} && echo '✓ K8s Worker-1 ({{ k8s_worker1_ip }})' || echo '✗ K8s Worker-1 ({{ k8s_worker1_ip }})'"
    ssh {{ target }} "ping -c 2 {{ k8s_worker2_ip }} && echo '✓ K8s Worker-2 ({{ k8s_worker2_ip }})' || echo '✗ K8s Worker-2 ({{ k8s_worker2_ip }})'"

# =============================================================================
# Initial Setup (One-time operations)
# =============================================================================

# Generate SSH key on homelab server if not exists
setup-ssh-key:
    #!/usr/bin/env bash
    echo "🔑 Setting up SSH key on homelab server..."
    ssh {{ target }} 'bash -s' << 'EOF'
    # Check for any existing SSH keys (ed25519, rsa, homelab.pem)
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        echo "✓ SSH key already exists: ~/.ssh/id_ed25519"
        echo ""
        echo "Public key:"
        cat ~/.ssh/id_ed25519.pub
    elif [ -f ~/.ssh/homelab.pem.pub ]; then
        echo "✓ SSH key already exists: ~/.ssh/homelab.pem"
        echo ""
        echo "Public key:"
        cat ~/.ssh/homelab.pem.pub
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        echo "✓ SSH key already exists: ~/.ssh/id_rsa"
        echo ""
        echo "Public key:"
        cat ~/.ssh/id_rsa.pub
    else
        echo "Generating new SSH key..."
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
        echo "✓ SSH key generated: ~/.ssh/id_ed25519"
        echo ""
        echo "Public key:"
        cat ~/.ssh/id_ed25519.pub
    fi
    EOF

# Create VM storage directories on host
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
# Version Management & Rollback
# =============================================================================

# List all system generations with timestamps
version-list:
    @echo "📋 System Generations on {{ target }}:"
    @echo ""
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system"

# Show current generation details
version-current:
    @echo "📍 Current System Generation:"
    @echo ""
    @echo "Generation Link:"
    ssh {{ target }} "readlink /run/current-system"
    @echo ""
    @echo "NixOS Version:"
    ssh {{ target }} "nixos-version"
    @echo ""
    @echo "Kernel Version:"
    ssh {{ target }} "uname -r"

# Rollback to previous generation
version-rollback:
    #!/usr/bin/env bash
    set -e
    echo "🔄 Rolling back to previous generation..."
    echo ""
    echo "=== Current Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5"
    echo ""

    read -p "Continue with rollback? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Rollback cancelled"
        exit 1
    fi

    echo "⏳ Stopping all MicroVMs..."
    ssh {{ target }} "sudo systemctl stop 'microvm@*'"

    echo "🔄 Switching to previous generation..."
    ssh {{ target }} "sudo nix-env --rollback --profile /nix/var/nix/profiles/system"

    echo "⚙️  Activating configuration..."
    ssh {{ target }} "sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch"

    echo "🚀 Starting MicroVMs..."
    ssh {{ target }} "sudo systemctl start 'microvm@vault' 'microvm@jenkins' 'microvm@registry' 'microvm@k8s-master' 'microvm@k8s-worker-1' 'microvm@k8s-worker-2'" || true

    echo ""
    echo "⏳ Waiting for VMs to stabilize..."
    sleep 10

    echo ""
    echo "=== New Current Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -3"

    echo ""
    echo "=== MicroVM Status ==="
    ssh {{ target }} "systemctl list-units 'microvm@*' --no-pager"

    echo ""
    echo "✅ Rollback completed!"

# Rollback to specific generation number
version-rollback-to generation:
    #!/usr/bin/env bash
    set -e
    echo "🔄 Rolling back to generation {{ generation }}..."
    echo ""

    # Check if generation exists
    if ! ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep -q '^\s*{{ generation }}\s'"; then
        echo "❌ Error: Generation {{ generation }} does not exist"
        echo ""
        echo "Available generations:"
        ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system"
        exit 1
    fi

    echo "=== Current Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '(current)'"
    echo ""
    echo "=== Target Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '^\s*{{ generation }}\s'"
    echo ""

    read -p "Continue with rollback to generation {{ generation }}? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Rollback cancelled"
        exit 1
    fi

    echo "⏳ Stopping all MicroVMs..."
    ssh {{ target }} "sudo systemctl stop 'microvm@*'"

    echo "🔄 Switching to generation {{ generation }}..."
    ssh {{ target }} "sudo nix-env --switch-generation {{ generation }} --profile /nix/var/nix/profiles/system"

    echo "⚙️  Activating configuration..."
    ssh {{ target }} "sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch"

    echo "🚀 Starting MicroVMs..."
    ssh {{ target }} "sudo systemctl start 'microvm@vault' 'microvm@jenkins' 'microvm@registry' 'microvm@k8s-master' 'microvm@k8s-worker-1' 'microvm@k8s-worker-2'" || true

    echo ""
    echo "⏳ Waiting for VMs to stabilize..."
    sleep 10

    echo ""
    echo "=== New Current Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -3"

    echo ""
    echo "=== MicroVM Status ==="
    ssh {{ target }} "systemctl list-units 'microvm@*' --no-pager"

    echo ""
    echo "=== Connectivity Test ==="
    just vm-ping

    echo ""
    echo "✅ Rollback to generation {{ generation }} completed!"

# Rollback to specific generation with system reboot (safer for major changes)
version-rollback-reboot generation:
    #!/usr/bin/env bash
    set -e
    echo "🔄 Rolling back to generation {{ generation }} with reboot..."
    echo ""

    # Check if generation exists
    if ! ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep -q '^\s*{{ generation }}\s'"; then
        echo "❌ Error: Generation {{ generation }} does not exist"
        echo ""
        echo "Available generations:"
        ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system"
        exit 1
    fi

    echo "=== Current Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '(current)'"
    echo ""
    echo "=== Target Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '^\s*{{ generation }}\s'"
    echo ""
    echo "⚠️  This will reboot the entire homelab system!"
    echo ""

    read -p "Continue with rollback and reboot? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Rollback cancelled"
        exit 1
    fi

    echo "⏳ Stopping all MicroVMs..."
    ssh {{ target }} "sudo systemctl stop 'microvm@*'"

    echo "🔄 Switching to generation {{ generation }}..."
    ssh {{ target }} "sudo nix-env --switch-generation {{ generation }} --profile /nix/var/nix/profiles/system"

    echo "⚙️  Activating configuration..."
    ssh {{ target }} "sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch"

    echo "🔄 Rebooting homelab... (SSH connection will close)"
    ssh {{ target }} "sudo reboot" || true

    echo ""
    echo "⏳ Waiting for homelab to come back online..."
    sleep 30
    until ssh -o ConnectTimeout=2 {{ target }} "exit" 2>/dev/null; do
        echo "Still waiting for {{ target }}..."
        sleep 5
    done

    echo ""
    echo "✨ Homelab is back! Verifying system..."
    echo ""
    echo "=== Current Generation ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -3"

    echo ""
    echo "=== MicroVM Status ==="
    ssh {{ target }} "systemctl list-units 'microvm@*' --no-pager"

    echo ""
    echo "=== Connectivity Test ==="
    just vm-ping

    echo ""
    echo "✅ Rollback to generation {{ generation }} with reboot completed!"

# Compare two generations (show package changes)
version-diff from to:
    #!/usr/bin/env bash
    echo "🔍 Comparing generation {{ from }} → {{ to }}..."
    echo ""

    # Check if generations exist
    if ! ssh {{ target }} "test -L /nix/var/nix/profiles/system-{{ from }}-link"; then
        echo "❌ Error: Generation {{ from }} does not exist"
        exit 1
    fi

    if ! ssh {{ target }} "test -L /nix/var/nix/profiles/system-{{ to }}-link"; then
        echo "❌ Error: Generation {{ to }} does not exist"
        exit 1
    fi

    echo "=== Generation {{ from }} ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '^\s*{{ from }}\s'" || echo "Generation {{ from }}"
    echo ""
    echo "=== Generation {{ to }} ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '^\s*{{ to }}\s'" || echo "Generation {{ to }}"
    echo ""
    echo "=== Package Changes ==="
    ssh {{ target }} "nix store diff-closures /nix/var/nix/profiles/system-{{ from }}-link /nix/var/nix/profiles/system-{{ to }}-link"

# Compare specific generation with current
version-compare-current generation:
    #!/usr/bin/env bash
    echo "🔍 Comparing generation {{ generation }} with current..."
    echo ""

    # Get current generation number
    current=$(ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '(current)' | awk '{print \$1}'")

    echo "Current generation: $current"
    echo "Target generation: {{ generation }}"
    echo ""

    just version-diff {{ generation }} $current

# Cleanup old generations (keep recent N generations)
version-cleanup days:
    #!/usr/bin/env bash
    echo "🧹 Cleaning up generations older than {{ days }} days..."
    echo ""
    echo "=== Generations to be deleted ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system" | while read line; do
        gen_date=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}')
        if [ ! -z "$gen_date" ]; then
            gen_age=$(( ($(date +%s) - $(date -d "$gen_date" +%s)) / 86400 ))
            if [ $gen_age -gt {{ days }} ] && ! echo "$line" | grep -q "(current)"; then
                echo "$line (age: ${gen_age} days)"
            fi
        fi
    done
    echo ""

    read -p "Continue with cleanup? This will delete old generations. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cleanup cancelled"
        exit 1
    fi

    echo "🗑️  Deleting old generations..."
    ssh {{ target }} "sudo nix-env --delete-generations {{ days }}d --profile /nix/var/nix/profiles/system"

    echo "♻️  Running garbage collection..."
    ssh {{ target }} "sudo nix-collect-garbage"

    echo "✨ Optimizing nix store..."
    ssh {{ target }} "sudo nix-store --optimise"

    echo ""
    echo "=== Remaining Generations ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system"

    echo ""
    echo "=== Disk Usage ==="
    ssh {{ target }} "df -h /nix"

    echo ""
    echo "✅ Cleanup completed!"

# Delete specific generation
version-delete generation:
    #!/usr/bin/env bash
    set -e
    echo "🗑️  Deleting generation {{ generation }}..."
    echo ""

    # Check if trying to delete current generation
    if ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '^\s*{{ generation }}\s' | grep -q '(current)'"; then
        echo "❌ Error: Cannot delete current generation ({{ generation }})"
        echo "Please rollback to a different generation first"
        exit 1
    fi

    # Check if generation exists
    if ! ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep -q '^\s*{{ generation }}\s'"; then
        echo "❌ Error: Generation {{ generation }} does not exist"
        exit 1
    fi

    echo "=== Generation to delete ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '^\s*{{ generation }}\s'"
    echo ""

    read -p "Delete generation {{ generation }}? This cannot be undone. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deletion cancelled"
        exit 1
    fi

    echo "🗑️  Deleting generation {{ generation }}..."
    ssh {{ target }} "sudo nix-env --delete-generations {{ generation }} --profile /nix/var/nix/profiles/system"

    echo "♻️  Running garbage collection..."
    ssh {{ target }} "sudo nix-collect-garbage"

    echo ""
    echo "=== Remaining Generations ==="
    ssh {{ target }} "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -5"

    echo ""
    echo "✅ Generation {{ generation }} deleted!"

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

# Test connectivity from host to VMs
net-test-host-to-vm:
    #!/usr/bin/env bash
    echo "🔌 Testing Host → VM Connectivity"
    echo ""
    echo "=== VLAN 10 (Management) - Host to VMs ==="
    echo "Host VLAN10 Gateway"
    ssh {{ target }} "ping -c 2 -W 2 {{ vault_ip }} && echo '✓ Vault ({{ vault_ip }})' || echo '✗ Vault ({{ vault_ip }}) - FAILED'"
    ssh {{ target }} "ping -c 2 -W 2 {{ jenkins_ip }} && echo '✓ Jenkins ({{ jenkins_ip }})' || echo '✗ Jenkins ({{ jenkins_ip }}) - FAILED'"
    echo ""
    echo "=== VLAN 20 (Services) - Host to VMs ==="
    echo "Host VLAN20 Gateway"
    ssh {{ target }} "ping -c 2 -W 2 {{ registry_ip }} && echo '✓ Registry ({{ registry_ip }})' || echo '✗ Registry ({{ registry_ip }})'"
    ssh {{ target }} "ping -c 2 -W 2 {{ k8s_master_ip }} && echo '✓ K8s Master ({{ k8s_master_ip }})' || echo '✓ K8s Master ({{ k8s_master_ip }})'"

# Test VM internal network configuration (direct SSH)
net-test-vm-internal vm_name vm_ip:
    #!/usr/bin/env bash
    echo "🔧 Testing VM Internal Network: {{ vm_name }} ({{ vm_ip }})"
    echo ""
    echo "=== Checking if VM is running ==="
    if ! ssh {{ target }} "systemctl is-active microvm@{{ vm_name }} --quiet"; then
        echo "❌ VM {{ vm_name }} is not running!"
        exit 1
    fi
    echo "✓ VM is running"
    echo ""
    echo "=== Attempting direct SSH to VM ==="
    if ssh -J {{ target }} -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@{{ vm_ip }} "hostname"; then
        echo "✓ SSH connection successful"
        echo ""
        echo "=== VM IP Configuration ==="
        ssh -J {{ target }} -o StrictHostKeyChecking=no root@{{ vm_ip }} "ip addr show"
        echo ""
        echo "=== VM Route Table ==="
        ssh -J {{ target }} -o StrictHostKeyChecking=no root@{{ vm_ip }} "ip route show"
        echo ""
        echo "=== VM Network Services ==="
        ssh -J {{ target }} -o StrictHostKeyChecking=no root@{{ vm_ip }} "systemctl status systemd-networkd --no-pager"
    else
        echo "✗ SSH connection failed - VM network not initialized"
        echo ""
        echo "=== Checking VM logs ==="
        ssh {{ target }} "journalctl -u microvm@{{ vm_name }} -n 50 --no-pager"
    fi

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
    just net-test-host-to-vm
    echo ""
    echo "=================================================="
    echo "6. Packet Forwarding & NAT"
    echo "=================================================="
    ssh {{ target }} "sudo sysctl net.ipv4.ip_forward"
    ssh {{ target }} "sudo iptables -t nat -L -n -v | head -20"

# Monitor real-time traffic on VLAN interfaces
net-monitor-traffic vlan="10":
    #!/usr/bin/env bash
    echo "📊 Monitoring VLAN {{ vlan }} Traffic (Press Ctrl+C to stop)"
    echo ""
    ssh {{ target }} -t "sudo tcpdump -i vlan{{ vlan }} -n"

# Monitor bridge traffic
net-monitor-bridge:
    #!/usr/bin/env bash
    echo "📊 Monitoring Bridge Traffic (Press Ctrl+C to stop)"
    echo ""
    ssh {{ target }} -t "sudo tcpdump -i vmbr0 -e -n vlan"

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
    echo "⚠️  WARNING: This will restart systemd-networkd on the host!"
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
    just net-check-networkd

# =============================================================================
# Utilities
# =============================================================================

# SSH to homelab server
ssh:
    ssh {{ target }}

# Show system status
status:
    ssh {{ target }} "nixos-version && uptime && df -h / && free -h"

# Clean old generations (keep last 3)
clean:
    ssh {{ target }} "sudo nix-collect-garbage --delete-older-than 7d && sudo nix-store --optimise"

# Show running VMs resource usage
vm-top:
    ssh {{ target }} "ps aux | grep -E '(qemu|virtiofsd)' | grep -v grep"
