# modules/ - NixOS 및 Home-manager 모듈

시스템 설정을 기능별로 분리한 재사용 가능한 모듈입니다.

## 구조

```
modules/
├── nixos/
│   ├── boot.nix              # 부트로더, IOMMU
│   ├── locale.nix            # 타임존, 로케일
│   ├── network.nix           # VLAN, 방화벽, TAP
│   ├── ssh.nix               # SSH 서버
│   ├── sops.nix              # 시크릿 관리
│   ├── nix-settings.nix      # Nix 데몬, GC
│   ├── users.nix             # 사용자 계정
│   ├── microvm-storage.nix   # VM 스토리지 디렉토리
│   ├── amdgpu.nix            # AMD GPU + ROCm
│   ├── tailscale.nix          # Tailscale VPN + Exit Node
│   ├── k8s-kubeadm-base.nix  # kubeadm 기반 K8s
│   └── k8s-worker-host.nix   # 호스트 K8s worker
│
├── home-manager/
│   ├── shell.nix             # Zsh (domains에서 설정 로드)
│   ├── editor.nix            # Neovim (domains에서 설정 로드)
│   ├── file-explorer.nix     # Yazi, fzf
│   └── utils.nix             # Git, 유틸리티
│
└── virtualization.nix        # KVM/QEMU, Podman
```

## Domain 연동

Home-manager 모듈은 `lib/domains/`에서 설정을 로드합니다:

```nix
# modules/home-manager/shell.nix
shellDomain = import ../../lib/domains/shell.nix;

programs.zsh.shellAliases = shellDomain.aliases;
```

이로써 NixOS와 Home-manager 간 설정 중복이 제거됩니다.

## 주요 모듈

### amdgpu.nix

AMD GPU + ROCm 설정:
- amdgpu 커널 드라이버
- ROCm 런타임 (HIP, OpenCL)
- Ollama GPU 가속 지원

### tailscale.nix

Tailscale VPN 및 Exit Node 설정:
- Tailscale 서비스 활성화 및 SSH 접속
- sops-nix 기반 자동 인증 (OAuth client secret)
- Exit Node 광고 (`--advertise-exit-node`)
- `--netfilter-mode=nodivert` 사용 (Bridge/VLAN 보호)
- Exit Node용 수동 MASQUERADE NAT 규칙

> **주의:** `nodivert` 모드에서는 Tailscale이 NAT 규칙을 자동 생성하지 않습니다.
> Exit Node 동작을 위해 `extraCommands`로 MASQUERADE 규칙을 수동 추가합니다.
> 자세한 내용은 `tailscale.nix` 내 주석을 참고하세요.

### k8s-kubeadm-base.nix

kubeadm 기반 K8s 노드 공통 설정:
- containerd 런타임
- kubelet systemd 서비스
- 필수 커널 모듈 및 sysctl

### k8s-worker-host.nix

호스트에서 K8s worker로 참여:
- kubeadm join 설정
- GPU 노드 레이블

## 새 모듈 추가

```nix
# modules/nixos/my-module.nix
{ config, pkgs, ... }: {
  # 설정 내용
}

# configuration.nix에서 import
imports = [ ./modules/nixos/my-module.nix ];
```
