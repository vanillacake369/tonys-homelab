# Variables

ssh_public_key := `if [ -f secrets/ssh-public-key.txt ]; then cat secrets/ssh-public-key.txt; else echo ""; fi`
ssh_key := "~/.ssh/homelab.pem"
nixos_user := "limjihoon"
flake_ref := ".#homelab"
nix_cmd := "SSH_PUB_KEY='" + ssh_public_key + "' nix"

# =============================================================================
# Host Commands
# =============================================================================

# Test configuration in VM
test:
    {{ nix_cmd }} run github:nix-community/nixos-anywhere -- --flake {{ flake_ref }} --vm-test --impure

# Deploy to bare-metal (DESTRUCTIVE!)
deploy target_ip:
    #!/usr/bin/env bash
    echo "⚠️  WARNING: This will ERASE ALL DATA on {{ target_ip }}"
    read -p "Press Enter to continue..."
    SSH_PUB_KEY='{{ ssh_public_key }}' nix run github:nix-community/nixos-anywhere -- \
        --build-on-remote \
        --flake {{ flake_ref }} \
        --build-args "--impure" \
        --impure \
        nixos@{{ target_ip }}

# Update remote system
update target_ip:
    NIX_SSHOPTS="-i {{ ssh_key }}" SSH_PUB_KEY='{{ ssh_public_key }}' nixos-rebuild switch \
        --flake {{ flake_ref }} \
        --target-host {{ nixos_user }}@{{ target_ip }} \
        --build-host {{ nixos_user }}@{{ target_ip }} \
        --sudo \
        --impure

# Local rebuild (run on server)
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
