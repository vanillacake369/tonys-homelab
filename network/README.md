# network/ — 네트워크 토폴로지 facts/projections

VLAN, Tailscale, Kubernetes, VM/호스트 네트워크 할당을 얕은 desired fact로 관리합니다.
CIDR 충돌 방지와 외부 도구(justfile, ansible) 연동을 위한 중앙 레지스트리이며,
derived view는 `projections.nix`에서 계산합니다.

```nix
# 사용 예
network = import ../../network/topology.nix;
projections = import ../../network/projections.nix { topology = network; };
network.hosts.homelab-1.uplink.ip  # → "192.168.45.82"
network.hosts.homelab-1.vlans.services.address  # → "10.0.20.1"
network.vms.k8s-master-1.ip    # → "10.0.20.10"
network.hosts.homelab-1.user   # → "limjihoon"
projections.vmsForHost "homelab-1"
```

## Table of Contents

- [WHAT](#what)

## WHAT

`topology.nix`는 순수 Nix attrset (NixOS 모듈 아님)이며 사람이 결정한 fact만 둡니다.
`projections.nix`는 topology에서 파생되는 query/view를 둡니다.

```mermaid
flowchart LR
  Topo["topology.nix"]
  Proj["projections.nix"]

  Topo -->|"hosts.*.uplink, vlans"| Host["homelab-1.nix"]
  Topo -->|"vms.*.ip/mac/tapId"| VMs["nodes/vms/*.nix"]
  Topo -->|"vms, kubernetes"| Ansible["ansible/inventory.nix"]
  Topo -->|"hosts, vms"| Resolve["lib/resolve-node.nix"]
  Topo -->|"tailscale.network"| TS["atoms/network/tailscale.nix"]
  Topo --> Proj
  Proj -->|"vmsForHost"| Host

  style Topo fill:#ffd,stroke:#333
  style Proj fill:#eef,stroke:#333
```

| 섹션 | 내용 | 참조처 |
|------|------|--------|
| `dns` | DNS 서버 | VM 네트워크 설정 |
| `vlans` | VLAN 10 (관리) / 20 (서비스) | homelab-1.nix, VM 네트워크 |
| `tailscale` | Tailscale CGNAT 대역 + 호스트 IP | tailscale.nix |
| `kubernetes` | Pod/Service CIDR, API VIP, Cilium 버전 | ansible inventory |
| `hosts` | 물리 호스트 {user, uplink, vlans} | resolve-node.nix, justfile |
| `vms` | VM별 {ip, mac, tapId} | VM nix 파일, homelab-1.nix TAP, ansible |
| `projections.vmsForHost` | host별 VM view | homelab-1.nix, justfile verify |
