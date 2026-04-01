# Tony's Homelab - High Efficiency Justfile (Self-contained)
# Single source of truth for all operations

# Data Extraction (SSOT)
_nix_eval expr:
    @nix eval --impure --raw --expr 'let d = import ./data; in {{ expr }}'

vms         := `nix eval --impure --raw --expr 'let d = import ./data; in builtins.concatStringsSep " " d.vms.order'`
target      := `nix eval --impure --raw --expr 'let d = import ./data; in d.network.wan.host'`
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
