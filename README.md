# Tony's Homelab

NixOS + libvirt + Colmena 기반 선언적 홈랩 인프라.
물리 서버 위에 libvirt QEMU/KVM으로 Kubernetes 클러스터를 운영합니다.

```bash
just deploy-all    # 물리호스트 → VM 순서로 전체 배포
just ssh k8s-master-1  # VM SSH 접속
just k8s-deploy    # K8s 클러스터 부트스트랩
```

## Table of Contents

- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Quick Start](#quick-start)
- [Operations](#operations)

## Architecture

```mermaid
flowchart TB
  subgraph Mac["Dev Machine (Mac)"]
    Colmena["Colmena CLI"]
    Just["justfile"]
  end

  subgraph Host["homelab-1 (Physical NixOS Host)"]
    Libvirt["libvirtd"]
    Bridge["vmbr0 Bridge"]
    TS["Tailscale Exit Node"]
    SOPS["sops-nix Secrets"]

    subgraph VLAN20["VLAN 20: Services (10.0.20.0/24)"]
      M1["k8s-master-1<br/>10.0.20.10"]
      M2["k8s-master-2<br/>10.0.20.11"]
      M3["k8s-master-3<br/>10.0.20.12"]
      W1["k8s-worker-1<br/>10.0.20.21"]
      W2["k8s-worker-2<br/>10.0.20.22"]
      W3["k8s-worker-3<br/>10.0.20.23"]
    end
  end

  subgraph WAN["WAN (192.168.45.0/24)"]
    GW["Gateway .1"]
  end

  Just --> Colmena
  Colmena -->|"deploy (SSH)"| Host
  Colmena -->|"deploy (ProxyJump)"| VLAN20
  Libvirt -->|"QEMU/KVM"| VLAN20
  Host --- Bridge --- VLAN20
  Host --- GW
  TS -.->|"VPN fallback"| Mac
```

**핵심 구성요소:**

| 구성 | 설명 | 참조 |
|------|------|------|
| [Colmena](https://github.com/zhaofengli/colmena) | NixOS 원격 배포 | `lib/mk-colmena.nix` |
| [libvirt](https://libvirt.org/) | VM 관리 (QEMU/KVM) | `lib/mk-libvirt.nix` |
| [sops-nix](https://github.com/Mic92/sops-nix) | 암호화된 시크릿 | `atoms/system/sops.nix` |
| IaC Contract | 노드별 옵션 인터페이스 | `nodes/interface.nix` |

## Directory Structure

```
.
├── flake.nix                  # Nix Flake 진입점
├── justfile                   # 운영 명령어 (deploy, ssh, k8s, ...)
├── network/
│   └── topology.nix           # CIDR/VLAN/호스트/VM 네트워크 상수
├── lib/                       # Colmena hive + libvirt 빌드 헬퍼
├── nodes/                     # IaC Contract + 노드 정의 (물리/VM/역할)
├── atoms/                     # 재사용 가능한 NixOS 모듈 조각
├── ansible/                   # K8s 부트스트랩 (kubeadm + Cilium)
└── secrets/                   # sops-nix 암호화 시크릿
```

각 디렉토리의 상세 설명은 디렉토리 내 `README.md`를 참조하세요.

## Quick Start

### 사전 요구

- Nix (flakes), sops, age, just, jq, tailscale

### SSH 설정 (필수)

Colmena와 justfile이 물리 호스트에 접속할 때 **LAN → Tailscale 자동 fallback**을 사용합니다.
`~/.ssh/config`에 다음을 추가하세요:

```ssh-config
# 물리 호스트: LAN(192.168.45.82) 우선, 실패 시 Tailscale IP 동적 파싱
Host homelab-1
  User limjihoon
  IdentityFile ~/.ssh/homelab.pem
  ProxyCommand bash -c 'timeout 2 nc 192.168.45.82 22 2>/dev/null || nc $(tailscale status --json 2>/dev/null | jq -r ".Peer[] | select(.DNSName | startswith(\"homelab-1.\")) | .TailscaleIPs[0]") 22'

# VM: 물리 호스트 경유 ProxyJump
Host 10.0.20.* k8s-master-* k8s-worker-*
  User root
  ProxyJump homelab-1
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

이 설정으로:
- **LAN에 있을 때**: 직접 SSH (2초 내 연결)
- **외부 네트워크**: Tailscale VPN 경유 (자동 감지, IP 변경 대응)
- **VM 접속**: 물리 호스트를 자동 경유 (ProxyJump)

### 배포

```bash
# 검증
just check

# 전체 배포 (호스트 → VM 순서)
just deploy-all

# 특정 노드만 배포
just deploy homelab-1
just deploy k8s-master-1 k8s-worker-1

# 빌드만 (적용 없음)
just build
```

## Operations

```bash
# SSH (LAN/Tailscale 자동 감지)
just ssh homelab-1        # 물리 호스트
just ssh k8s-master-1     # VM (ProxyJump 자동)

# VM 관리
just vm start k8s-master-1
just vm stop all
just vm-status

# 시스템 점검
just status               # 전체 건강 상태
just net                  # 네트워크 토폴로지
just k8s-verify           # K8s 클러스터 상세 점검

# K8s 클러스터
just k8s-deploy           # clean → bootstrap → verify
just k8s-bootstrap        # 초기 부트스트랩
just k8s-clean            # 클러스터 리셋

# 유지보수
just gc                   # 전체 노드 가비지 컬렉션
just gc homelab-1         # 특정 노드만
just update               # flake 업데이트
```
