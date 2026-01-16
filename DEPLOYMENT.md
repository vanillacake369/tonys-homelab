# Deployment Guide

This homelab uses **Colmena** for declarative, multi-node deployment.

## Quick Start

### Initial Setup

1. **Deploy to bare-metal** (one-time, destructive):
```bash
just deploy <target-ip>
```

### Day-to-Day Operations

2. **Deploy configuration changes** (recommended):
```bash
just deploy
```

This will deploy to all nodes tagged with `@homelab`.

### Colmena Commands

```bash
# Deploy to all nodes
just deploy

# Deploy to specific node
just deploy-node homelab

# Deploy with verbose output (debugging)
just deploy-verbose

# Build without deploying (dry-run)
just build

# Show deployment info
just info

# Deploy only to physical servers
just deploy-physical

# Future: Deploy only to VMs
just deploy-vms
```

## Architecture

### Current Setup

- **homelab** (physical server)
  - Tags: `physical`, `homelab`
  - Hostname: `homelab.local`
  - User: `limjihoon`
  - Build: On target (saves local resources)

### Future: MicroVM Expansion

When adding microVMs, they will be configured like:

```nix
# flake.nix
colmena = {
  # ... existing homelab config ...

  vm-node-1 = {
    deployment = {
      targetHost = "vm-node-1.local";
      targetUser = "admin";
      buildOnTarget = true;
      tags = ["vm" "kubernetes"];
    };
    imports = [ ./vms/node-1.nix ];
  };
};
```

Then deploy with:
```bash
just deploy-vms  # Only VMs
just deploy      # All nodes (physical + VMs)
```

## SSH Configuration

Colmena uses SSH keys defined in justfile:
- Key: `~/.ssh/homelab.pem`
- Passed via `NIX_SSHOPTS`

Update `targetHost` in `flake.nix` to match your server's IP or hostname:
```nix
deployment.targetHost = "192.168.45.82";  # or "homelab.local"
```

## Troubleshooting

### Cannot connect to host

1. Check SSH connectivity:
```bash
ssh -i ~/.ssh/homelab.pem limjihoon@homelab.local
```

2. Update targetHost in `flake.nix` if hostname doesn't resolve:
```nix
deployment.targetHost = "192.168.45.82";
```

### Build fails

Run with verbose output:
```bash
just deploy-verbose
```

### Legacy deployment method

If Colmena fails, fallback to direct SSH:
```bash
just update <target-ip>
```

## Benefits of Colmena

✅ **Parallel deployment** - Deploy to multiple nodes simultaneously
✅ **Tag-based selection** - Deploy to subsets (physical/vm/production)
✅ **Built-in secrets** - Manage secrets with `deployment.keys`
✅ **Rollback support** - Easy rollback on failures
✅ **Build on target** - No need for powerful local machine
✅ **Future-proof** - Ready for microVM expansion
