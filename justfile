set shell := ["bash", "-euo", "pipefail", "-c"]

topology := "./network/topology.nix"

# [최적화] 무거운 NixOS 구성을 불러오지 않고 Topology 상수만 읽어와서 속도 극대화
ssh-config := ```
  mkdir -p .cache
  config_file=".cache/ssh-config"
  
  # 가벼운 topology.nix만 eval (OS 설정 로딩 제거)
  nix eval --impure --json --expr "(import ./network/topology.nix)" | jq -r '
    (.hosts | to_entries[] | "Host \(.key)\n    HostName \(.value.ip)\n    User \(.value.user)\n    StrictHostKeyChecking no\n"),
    (.vms | to_entries[] | "Host \(.key) \(.value.ip)\n    HostName \(.value.ip)\n    User root\n    ProxyJump \(.value.host)\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n")
  ' > "$config_file"

  echo "$config_file"
```

# =============================================================================
# Private: 인프라 헬퍼
# =============================================================================

[private]
_colmena +args:
    SSH_CONFIG_FILE={{ ssh-config }} nix run --impure .#colmena -- {{ args }}

[private]
_ssh node +cmd:
    ssh -F {{ ssh-config }} {{ node }} {{ cmd }}

# =============================================================================
# Deploy
# =============================================================================

deploy-all: deploy-host deploy-vms

deploy-host:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r 'join(",")')
    just _colmena apply --on "$targets" --verbose

deploy-vms:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r 'join(",")')
    just _colmena apply --on "$targets" --verbose

deploy +nodes:
    just _colmena apply --on "$(echo "{{ nodes }}" | tr ' ' ',')" --verbose

# =============================================================================
# VM Image Provisioning
# =============================================================================

build-images *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    remote_dir="/tmp/homelab-build"
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    
    targets="{{ vms }}"
    if [ -z "$targets" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".host")
        echo "=== Building $vm on $host ==="
        just _ssh "$host" "rm -rf $remote_dir"
        rsync -az --filter=':- .gitignore' --exclude='.git' -e "ssh -F {{ ssh-config }}" . "$host:$remote_dir/"
        just _ssh "$host" "cd $remote_dir && nix build --impure '.#$vm' -o /tmp/image-$vm"
        just _ssh "$host" "sudo mkdir -p /var/lib/libvirt/images/base && sudo cp /tmp/image-$vm/*.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
        just _ssh "$host" "rm -rf /tmp/image-$vm $remote_dir"
        echo "  $vm: OK"
    done

provision-vms *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    ssh_timeout_s="${PROVISION_SSH_TIMEOUT:-300}"
    
    targets="{{ vms }}"
    if [ -z "$targets" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".host")
        ip=$(echo "$data" | jq -r ".\"$vm\".ip")
        echo "=== Provisioning $vm on $host ($ip) ==="
        just _ssh "$host" "sudo virsh destroy $vm 2>/dev/null || true; \
                           sudo rm -f /var/lib/libvirt/images/$vm.qcow2; \
                           sudo systemctl restart vm-$vm.service"
        
        printf "  Waiting for SSH..."
        start_ts=$(date +%s)
        while true; do
            if just _ssh "$host" "nc -zvw1 $ip 22" &>/dev/null; then echo " OK"; break; fi
            if [ $(( $(date +%s) - start_ts )) -ge "$ssh_timeout_s" ]; then echo " TIMEOUT"; exit 1; fi
            sleep 2; printf "."
        done
    done

# =============================================================================
# Access & Lifecycle
# =============================================================================

ssh node:
    ssh -F {{ ssh-config }} {{ node }}

vm action name="all":
    #!/usr/bin/env bash
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    targets="{{ name }}"
    if [ "{{ name }}" = "all" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".host")
        case "{{ action }}" in
            start|stop|restart) cmd="sudo systemctl {{ action }} vm-$vm.service" ;;
            *) cmd="sudo virsh {{ action }} $vm" ;;
        esac
        echo "$vm: {{ action }}ing on $host..."
        just _ssh "$host" "$cmd" &
    done
    wait

# =============================================================================
# Status & Network
# =============================================================================

status:
    #!/usr/bin/env bash
    nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]' | while read -r host; do
        echo "=== Host: $host ==="
        just _ssh "$host" "uptime && echo && df -h / /nix/store 2>/dev/null" || echo "Unreachable"
        echo ""
    done
    just vm-status

vm-status:
    #!/usr/bin/env bash
    echo "=== VM Status ==="
    nix eval --impure --json --expr "(import {{ topology }}).vms" | jq -r 'to_entries[] | "\(.key) \(.value.ip) \(.value.host)"' | while read -r name ip host; do
        if just _ssh "$host" "nc -zvw2 $ip 22" &>/dev/null; then
            echo "  $name ($ip) on $host: OK"
        else
            echo "  $name ($ip) on $host: UNREACHABLE"
        fi
    done

net:
    #!/usr/bin/env bash
    nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]' | while read -r host; do
        echo "=== Network: $host ==="
        just _ssh "$host" "bridge vlan show 2>/dev/null; echo; networkctl list; echo; ip route"
        echo ""
    done

# =============================================================================
# Maintenance
# =============================================================================

check:
    nix flake check --impure --all-systems

update:
    nix flake update

gc *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(if [ -z "{{ nodes }}" ]; then nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)' | jq -r '.[]'; else echo "{{ nodes }}"; fi)
    for node in $targets; do
        echo "=== GC: $node ==="
        just _ssh "$node" "sudo nix-collect-garbage -d && sudo nix-store --optimize && sudo journalctl --vacuum-time=1d" || echo "Failed"
    done
