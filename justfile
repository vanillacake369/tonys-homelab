# Tony's Homelab - Justfile
# Development and Production deployment recipes
# Variables dynamically evaluated from Nix constants
# Single source of truth: lib/homelab-constants.nix and flake.nix

ssh_public_key := `if [ -f secrets/ssh-public-key.txt ]; then cat secrets/ssh-public-key.txt; else echo "Error: Missing secrets/ssh-public-key.txt" >&2; exit 1; fi`

# SSH target: Auto-detect from ~/.ssh/config by matching WAN IP

vm_list := `nix eval --impure --raw --expr 'let constants = (builtins.getFlake (toString ./.)).homelabConstants; in builtins.concatStringsSep " " (builtins.attrNames constants.vms)' || { echo "Error: Failed to read vm list from flake" >&2; exit 1; }`
vm_tag_list := `nix eval --impure --raw --expr 'let constants = (builtins.getFlake (toString ./.)).homelabConstants; in builtins.concatStringsSep " " (map (vm: "vm-" + vm) (builtins.attrNames constants.vms))' || { echo "Error: Failed to read vm tag list from flake" >&2; exit 1; }`
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

# =============================================================================
# Development Commands (Local Testing)
# =============================================================================

# Check flake configuration for errors
check:
    nix flake check --impure --all-systems --show-trace

_colmena cmd on_flag="" extra_flags="" microvm_targets="":
    #!/usr/bin/env bash
    set -euo pipefail
    MICROVM_TARGETS="{{ microvm_targets }}" SSH_PUB_KEY="{{ ssh_public_key }}" \
        nix run --impure .#colmena -- {{ cmd }} {{ extra_flags }} {{ on_flag }} --show-trace

_ssh cmd:
    ssh {{ target }} "{{ cmd }}"

_microvm_action action vm:
    just _ssh "sudo systemctl {{ action }} microvm@{{ vm }}"

_microvm_status:
    just _ssh "systemctl list-units 'microvm@*' --no-pager"

_microvm_wait_running:
    #!/usr/bin/env bash
    set -euo pipefail
    MAX_RETRIES=20
    echo "⏳ Waiting for VMs to respond to ping..."
    for ((i=1; i<=MAX_RETRIES; i++)); do
        ALL_UP=true
        for vm in {{ vm_list }}; do
            ip=$(just _vm_ip "$vm")
            if ! ssh {{ target }} "ping -c 1 -W 1 $ip >/dev/null 2>&1"; then
                ALL_UP=false
                break
            fi
        done
        if $ALL_UP; then
            echo "✅ All VMs are responding."
            exit 0
        fi
        if [ "$i" -eq "$MAX_RETRIES" ]; then
            echo "⚠️  Some VMs are not responding after ${MAX_RETRIES} attempts."
            just vm-ping
            exit 1
        fi
        echo "... waiting ($i/$MAX_RETRIES)"
        sleep 2
    done

_vm_ssh ip:
    ssh -J {{ target }} root@{{ ip }}

_vm_ip vm:
    @nix eval --impure --raw '.#homelabConstants.vms."{{ vm }}".ip' 2>/dev/null || { echo "Unknown VM: {{ vm }}" >&2; exit 1; }

# Build configuration locally (dry-run)
# Usage:
#   just build all                        # 전체 빌드 (server + 모든 VM)
#   just build server                     # 서버만 빌드 (VM 설정 포함)
#   just build server --no-vm             # 서버만 빌드 (VM 설정 제외)
#   just build server --server homelab-1  # 서버 노드 지정
#   just build vm                         # 모든 VM 빌드
#   just build vm vault                   # 특정 VM 빌드
#   just build vm k8s                     # K8S 클러스터 빌드 (태그)
build type="server" name="" server="homelab-1":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ type }}" in
        all)
            echo "🚀 Building server: {{ server }}"
            just _colmena build "--on {{ server }}" "--impure" "none"
            for vm in {{ vm_list }}; do
                echo "🚀 Building VM: $vm"
                just _colmena build "--on $vm" "--impure" "$vm"
            done
            ;;
        server)
            if [ "{{ name }}" = "--no-vm" ]; then
                just _colmena build "--on {{ server }}" "--impure" "none"
            else
                just _colmena build "--on {{ server }}" "--impure" "all"
            fi
            ;;
        vm)
            if [ -z "{{ name }}" ]; then
                just _colmena build "--on @$(echo '{{ vm_tag_list }}' | tr ' ' ',')" "--impure" ""
            elif [ "{{ name }}" = "k8s" ]; then
                just _colmena build "--on @k8s" "--impure" ""
            else
                just _colmena build "--on {{ name }}" "--impure" "{{ name }}"
            fi
            ;;
        *)
            echo "Usage: just build [all|server [--no-vm]|vm [name|k8s]]" >&2
            exit 1
            ;;
    esac

# Update flake inputs
update:
    nix flake update

# Show current infrastructure values
show-config:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== SSH Connection ==="
    echo "Detected Host: {{ target }}"
    echo "WAN IP:        $(nix eval --raw .#homelabConstants.networks.wan.host)"
    echo "Source:        ~/.ssh/config (auto-detected)"
    echo ""
    echo "=== Network Configuration ==="
    echo "WAN Network:   $(nix eval --raw .#homelabConstants.networks.wan.network)"
    echo "WAN Gateway:   $(nix eval --raw .#homelabConstants.networks.wan.gateway)"
    echo ""
    echo "=== VM IP Addresses ==="
    for vm in {{ vm_list }}; do
        ip=$(just _vm_ip "$vm")
        vlan=$(nix eval --impure --raw ".#homelabConstants.vms.\"$vm\".vlan")
        printf "%-20s %s (VLAN: %s)\n" "$vm:" "$ip" "$vlan"
    done

# =============================================================================
# Production Deployment
# =============================================================================
# Deploy configuration via Colmena
# Usage:
#   just deploy all                        # 전체 배포 (server + 모든 VM)
#   just deploy server                     # 서버만 배포 (VM 설정 포함)
#   just deploy server --no-vm             # 서버만 배포 (VM 설정 제외)
#   just deploy server --server homelab-1  # 서버 노드 지정
#   just deploy vm                         # 모든 VM 배포
#   just deploy vm vault                   # 특정 VM 배포
#   just deploy vm k8s                     # K8S 클러스터 배포 (태그)
deploy type="server" name="" server="homelab-1":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ type }}" in
        all)
            echo "🚀 Applying server: {{ server }}"
            just _colmena apply "--on {{ server }}" "--verbose --impure" "none"
            for vm in {{ vm_list }}; do
                echo "🚀 Applying VM: $vm"
                just _colmena apply "--on $vm" "--verbose --impure" "$vm"
            done
            ;;
        server)
            if [ "{{ name }}" = "--no-vm" ]; then
                just _colmena apply "--on {{ server }}" "--verbose --impure" "none"
            else
                just _colmena apply "--on {{ server }}" "--verbose --impure" "all"
            fi
            ;;
        vm)
            if [ -z "{{ name }}" ]; then
                just _colmena apply "--on @$(echo '{{ vm_tag_list }}' | tr ' ' ',')" "--verbose --impure" ""
            elif [ "{{ name }}" = "k8s" ]; then
                just _colmena apply "--on @k8s" "--verbose --impure" ""
            else
                just _colmena apply "--on {{ name }}" "--verbose --impure" "{{ name }}"
            fi
            ;;
        *)
            echo "Usage: just deploy [all|server [--no-vm]|vm [name|k8s]]" >&2
            exit 1
            ;;
    esac

# =============================================================================
# MicroVM Management
# =============================================================================

# Show all VMs status
vm-status:
    just _microvm_status

# Start VM(s)
# Usage:
#   just vm-start vault          # 특정 VM 시작
#   just vm-start all            # 모든 VM 시작
vm-start vm:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ vm }}" = "all" ]; then
        echo "🟢 Starting all MicroVMs on {{ target }}..."
        for vm in {{ vm_list }}; do
            echo "  Starting microvm@$vm..."
            ssh {{ target }} "sudo systemctl start microvm@$vm" &
        done
        wait
        echo "⏳ Waiting for VMs to stabilize..."
        just _microvm_wait_running
        just vm-status
    else
        just _microvm_action start {{ vm }}
    fi

# Stop VM(s)
# Usage:
#   just vm-stop vault           # 특정 VM 중지
#   just vm-stop all             # 모든 VM 중지
vm-stop vm:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ vm }}" = "all" ]; then
        echo "🛑 Stopping all MicroVMs..."
        for vm in {{ vm_list }}; do
            echo "  Stopping microvm@$vm..."
            ssh {{ target }} "sudo systemctl stop microvm@$vm" &
        done
        wait
        echo "⏳ Waiting for VMs to stop..."
        sleep 3
        echo "✓ All VMs stopped"
        just vm-status
    else
        just _microvm_action stop {{ vm }}
    fi

# Restart VM(s)
# Usage:
#   just vm-restart vault        # 특정 VM 재시작
#   just vm-restart all          # 모든 VM 재시작
vm-restart vm:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ vm }}" = "all" ]; then
        echo "🔄 Restarting all MicroVMs on {{ target }}..."
        for vm in {{ vm_list }}; do
            echo "  Restarting microvm@$vm..."
            ssh {{ target }} "sudo systemctl restart microvm@$vm" &
        done
        wait
        echo "⏳ Waiting for VMs to stabilize..."
        just _microvm_wait_running
        just vm-status
    else
        just _microvm_action restart {{ vm }}
    fi

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
    for vm in {{ vm_list }}; do
        ip=$(just _vm_ip "$vm")
        ssh {{ target }} "ping -c 2 -W 2 $ip >/dev/null 2>&1 && echo '✓ $vm ($ip)' || echo '✗ $vm ($ip)'" &
    done
    wait

# =============================================================================
# Initial Setup (One-time operations)
# =============================================================================

# Create VM storage directories on homelab
vm-setup-storage:
    #!/usr/bin/env bash
    set -euo pipefail
    storage_paths=$(nix eval --impure --raw --expr '
      let constants = (builtins.getFlake (toString ./.)).homelabConstants;
      in builtins.concatStringsSep " " (
        builtins.filter (x: x != "")
          (builtins.attrValues (builtins.mapAttrs
            (name: vm: vm.storage.source or "")
            constants.vms))
      )
    ')
    ssh {{ target }} "
        for path in $storage_paths; do
            sudo mkdir -p \"\$path\"
        done
        sudo chown -R root:kvm /var/lib/microvms
        sudo chmod -R 0755 /var/lib/microvms
        echo '✓ MicroVM storage directories created'
        ls -la /var/lib/microvms/
    "

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
    just vm-ping
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
