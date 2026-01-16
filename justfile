# Variables

ssh_public_key := `if [ -f secrets/ssh-public-key.txt ]; then cat secrets/ssh-public-key.txt; else echo ""; fi`
ssh_key := "~/.ssh/homelab.pem"
nixos_user := "limjihoon"
flake_ref := ".#homelab"
nix_cmd := "SSH_PUB_KEY='" + ssh_public_key + "' nix"

# =============================================================================
# Deployment Commands
# =============================================================================

# Test configuration in VM
test:
    {{ nix_cmd }} run github:nix-community/nixos-anywhere -- --flake {{ flake_ref }} --vm-test --impure

# Initial bare-metal installation (DESTRUCTIVE!)
install target_ip:
    #!/usr/bin/env bash
    echo "⚠️  WARNING: This will ERASE ALL DATA on {{ target_ip }}"
    read -p "Press Enter to continue..."
    SSH_PUB_KEY='{{ ssh_public_key }}' nix run github:nix-community/nixos-anywhere -- \
        --build-on-remote \
        --flake {{ flake_ref }} \
        --build-args "--impure" \
        --impure \
        nixos@{{ target_ip }}

# =============================================================================
# Colmena Deployment (recommended for homelab)
# =============================================================================

# Deploy to all nodes (uses ~/.ssh/config for authentication)
deploy:
    {{ nix_cmd }} run .#colmena -- apply --impure

# Deploy to specific node
deploy-node node:
    {{ nix_cmd }} run .#colmena -- apply --on {{ node }} --impure

# Deploy with verbose output
deploy-verbose:
    {{ nix_cmd }} run .#colmena -- apply --verbose --impure

# Build without deploying (dry-run)
build:
    {{ nix_cmd }} run .#colmena -- build --impure

# Show deployment info
info:
    {{ nix_cmd }} run .#colmena -- introspect

# Deploy only to physical servers (tag-based)
deploy-physical:
    {{ nix_cmd }} run .#colmena -- apply --on @physical --impure

# Future: Deploy only to VMs
deploy-vms:
    {{ nix_cmd }} run .#colmena -- apply --on @vm --impure

# =============================================================================
# Legacy System Updates (fallback method)
# =============================================================================

# Sync configuration files to remote
sync target_ip:
    rsync -avz --delete \
        -e "ssh -i {{ ssh_key }}" \
        --exclude '.git' \
        --exclude 'result' \
        --exclude '.direnv' \
        . {{ nixos_user }}@{{ target_ip }}:~/tonys-homelab/

# Update complete configuration (system + user) on remote - Legacy method
update target_ip:
    @just sync {{ target_ip }}
    ssh -i {{ ssh_key }} {{ nixos_user }}@{{ target_ip }} "cd ~/tonys-homelab && sudo SSH_PUB_KEY='{{ ssh_public_key }}' nixos-rebuild switch --flake {{ flake_ref }} --impure"

# Local rebuild (system + user) - run on server
rebuild:
    sudo SSH_PUB_KEY='{{ ssh_public_key }}' nixos-rebuild switch --flake {{ flake_ref }} --impure

# =============================================================================
# Utilities
# =============================================================================

# Show system status
status target_ip:
    ssh -i {{ ssh_key }} {{ nixos_user }}@{{ target_ip }} "nixos-version && uptime && df -h / && systemctl --failed"

# Clean old generations
clean target_ip generations="5":
    ssh -i {{ ssh_key }} {{ nixos_user }}@{{ target_ip }} "sudo nix-env --delete-generations +{{ generations }} -p /nix/var/nix/profiles/system && sudo nix-collect-garbage"

# Show config diff
diff target_ip:
    NIX_SSHOPTS="-i {{ ssh_key }}" nix run nixpkgs#nixos-rebuild -- build --flake {{ flake_ref }} --target-host {{ nixos_user }}@{{ target_ip }} --build-host {{ nixos_user }}@{{ target_ip }}
    ssh -i {{ ssh_key }} {{ nixos_user }}@{{ target_ip }} "nix store diff-closures /run/current-system ./result"

# SSH to server
ssh target_ip:
    ssh -i {{ ssh_key }} {{ nixos_user }}@{{ target_ip }}
