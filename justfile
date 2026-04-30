set shell := ["bash", "-euo", "pipefail", "-c"]

topology := "./network/topology.nix"

# [최적화] Topology 상수와 Tailscale 상태를 결합하여 최적의 경로 선택

ssh-config := ```
  mkdir -p .cache
  config_file=".cache/ssh-config"
  
  # 데이터 가져오기
  nix_data=$(nix eval --impure --json --expr "(import ./network/topology.nix)")
  ts_data_raw=$(tailscale status --json 2>/dev/null || true)
  if echo "$ts_data_raw" | jq -e . >/dev/null 2>&1; then
    ts_data="$ts_data_raw"
  else
    ts_data='{"Peer":[]}'
  fi

  # 물리 호스트 및 VM 설정 생성
  echo "$nix_data" | jq -r --argjson ts "$ts_data" '
    (.hosts | to_entries[] as $host |
      (($ts.Peer[]? | select(.HostName == $host.key or (.DNSName | startswith($host.key+"."))) | .TailscaleIPs[0]) // $host.value.ip) as $ip |
      "Host \($host.key)\n    HostName \($ip)\n    User \($host.value.user)\n    StrictHostKeyChecking no\n"),
    (.vms | to_entries[] as $vm | 
      "Host \($vm.key) \($vm.value.ip)\n    HostName \($vm.value.ip)\n    User root\n    ProxyJump \($vm.value.host)\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n")
  ' > "$config_file"

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

# -n: 표준 입력을 차단하여 while read 루프 내에서 사용 시 데이터 소모 방지
[private]
_ssh node +cmd:
    ssh -n -F {{ ssh-config }} {{ node }} {{ cmd }}

# Ansible wrapper
[private]
_ansible +args:
    ANSIBLE_LOCAL_TEMP="/tmp/ansible-local" TMPDIR="/tmp" ANSIBLE_SSH_ARGS="-F {{ ssh-config }}" ansible-playbook -i ansible/inventory.py {{ args }}

# =============================================================================
# Deploy
# =============================================================================

# Deploy all (host first → VMs)
deploy-all: deploy-host deploy-vms

# Deploy physical host(s)
deploy-host:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r 'join(",")')
    just _colmena apply --on "$targets" --verbose

# Deploy all VMs
deploy-vms:
    #!/usr/bin/env bash
    targets=$(nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).vms' | jq -r 'join(",")')
    just _colmena apply --on "$targets" --verbose

# Deploy specific node(s): just deploy k8s-master-1
deploy +nodes:
    just _colmena apply --on "$(echo "{{ nodes }}" | tr ' ' ',')" --verbose

# =============================================================================
# VM Image Provisioning
# =============================================================================

# Build VM QCOW2 images on their respective hosts
build-images *vms:
    #!/usr/bin/env bash
    set -euo pipefail
    remote_dir="/tmp/homelab-build"
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    target_system=$(nix eval --raw --impure '.#targetSystem')

    targets="{{ vms }}"
    if [ -z "$targets" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".host")
        echo "=== Building $vm on $host (Target: $target_system) ==="
        ssh -n -F {{ ssh-config }} "$host" "rm -rf $remote_dir && mkdir -p $remote_dir"
        rsync -az --filter=':- .gitignore' --exclude='.git' -e "ssh -F {{ ssh-config }}" . "$host:$remote_dir/"
        ssh -n -F {{ ssh-config }} "$host" "cd $remote_dir && nix build --impure '.#packages.$target_system.$vm' --system $target_system -o /tmp/image-$vm"
        ssh -n -F {{ ssh-config }} "$host" "sudo mkdir -p /var/lib/libvirt/images/base && sudo cp /tmp/image-$vm/*.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
        ssh -n -F {{ ssh-config }} "$host" "rm -rf /tmp/image-$vm $remote_dir"
        echo "  $vm: OK"
    done

# Copy base image to local disk and restart VM service
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
        ssh -n -F {{ ssh-config }} "$host" "sudo virsh destroy $vm 2>/dev/null || true; \
                           sudo rm -f /var/lib/libvirt/images/$vm.qcow2; \
                           sudo systemctl restart vm-$vm.service"

        printf "  Waiting for SSH..."
        start_ts=$(date +%s)
        while true; do
            if ssh -n -F {{ ssh-config }} "$host" "nc -zvw1 $ip 22" &>/dev/null; then echo " OK"; break; fi
            if [ $(( $(date +%s) - start_ts )) -ge "$ssh_timeout_s" ]; then echo " TIMEOUT"; exit 1; fi
            sleep 2; printf "."
        done
    done

# =============================================================================
# Access & Lifecycle
# =============================================================================

# SSH into any node
ssh node:
    ssh -F {{ ssh-config }} {{ node }}

# VM lifecycle control via systemd (start|stop|restart|remove)
vm action name="all":
    #!/usr/bin/env bash
    data=$(nix eval --impure --json --expr "(import {{ topology }}).vms")
    targets="{{ name }}"
    if [ "{{ name }}" = "all" ]; then targets=$(echo "$data" | jq -r 'keys[]'); fi

    for vm in $targets; do
        host=$(echo "$data" | jq -r ".\"$vm\".host")
        case "{{ action }}" in
            start|stop|restart) cmd="sudo systemctl {{ action }} vm-$vm.service" ;;
            remove) 
                cmd="sudo systemctl stop vm-$vm.service 2>/dev/null || true; \
                     sudo virsh destroy $vm 2>/dev/null || true; \
                     sudo virsh undefine $vm --remove-all-storage 2>/dev/null || true; \
                     sudo rm -f /var/lib/libvirt/images/$vm.qcow2 /var/lib/libvirt/images/base/$vm.qcow2"
                ;;
            *) cmd="sudo virsh {{ action }} $vm" ;;
        esac
        echo "$vm: {{ action }}ing on $host..."
        just _ssh "$host" "$cmd" &
    done
    wait

# =============================================================================
# Status & Network
# =============================================================================

# System health (uptime and disk usage)
status:
    #!/usr/bin/env bash
    nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]' | while read -r host; do
        echo "=== Host: $host ==="
        just _ssh "$host" "uptime && echo && df -h / /nix/store 2>/dev/null" || echo "Unreachable"
        echo ""
    done
    just vm-status

# VM connectivity status
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

# Network configuration summary (VLANs, bridge, routes)
net:
    #!/usr/bin/env bash
    nix eval --impure --json --expr 'builtins.attrNames (import {{ topology }}).hosts' | jq -r '.[]' | while read -r host; do
        echo "=== Network: $host ==="
        just _ssh "$host" "bridge vlan show 2>/dev/null; echo; networkctl list; echo; ip route"
        echo ""
    done

# =============================================================================
# Kubernetes (Ansible)
# =============================================================================

# Full lifecycle: clean → bootstrap → verify
k8s-deploy: k8s-clean k8s-bootstrap k8s-verify

# Bootstrap cluster
k8s-bootstrap:
    just _ansible ansible/site.yml --tags bootstrap -v

# Reset cluster
k8s-clean:
    just _ansible ansible/site.yml --tags cleanup -e reset_cluster=true -v

# Cluster health check
k8s-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    master_ip=$(nix eval --impure --json --expr '(import {{ topology }}).vms' \
        | jq -r 'to_entries[] | select(.key | startswith("k8s-master")) | .value.ip' | head -1)
    api_vip=$(nix eval --impure --raw --expr '(import {{ topology }}).kubernetes.api_vip')

    kc() { ssh -F {{ ssh-config }} $master_ip "$*" 2>/dev/null; }

    echo "=== API Health (VIP: $api_vip) ==="
    kc "curl -sk https://$api_vip:6443/healthz" && echo " OK" || echo " UNHEALTHY"
    echo ""
    echo "=== Nodes ==="
    kc "kubectl get nodes -o wide" || echo "unavailable"
    echo ""
    echo "=== kube-system Pods ==="
    kc "kubectl get pods -n kube-system -o wide" || echo "unavailable"

# =============================================================================
# Maintenance
# =============================================================================

# Validate flake
check:
    nix flake check --impure --all-systems

# Update flake inputs
update:
    nix flake update

# Garbage collection on all or specific nodes
gc *nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(if [ -z "{{ nodes }}" ]; then nix eval --impure --json --expr 'let t = import {{ topology }}; in (builtins.attrNames t.hosts) ++ (builtins.attrNames t.vms)' | jq -r '.[]'; else echo "{{ nodes }}"; fi)
    for node in $targets; do
        echo "=== GC: $node ==="
        just _ssh "$node" "sudo nix-collect-garbage -d && sudo nix-store --optimize && sudo journalctl --vacuum-time=1d" || echo "Failed"
    done
