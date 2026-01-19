# modules/ - NixOS 및 Home-manager 모듈

시스템 설정을 기능별로 분리한 재사용 가능한 모듈입니다.

## 디렉토리 구조

```
modules/
├── nixos/                    # NixOS 시스템 모듈
│   ├── boot.nix              # 부트로더, KVM, IOMMU
│   ├── locale.nix            # 타임존, 로케일
│   ├── network.nix           # 네트워크, VLAN, 방화벽
│   ├── ssh.nix               # SSH 서버 설정
│   ├── sops.nix              # 시크릿 관리 (sops-nix)
│   ├── nix-settings.nix      # Nix 데몬, GC 설정
│   ├── users.nix             # 사용자 계정
│   └── microvm-storage.nix   # MicroVM 스토리지 디렉토리
│
├── home-manager/             # 사용자 환경 모듈
│   ├── shell.nix             # Zsh, Oh-My-Zsh, 별칭
│   ├── editor.nix            # Neovim 설정
│   ├── file-explorer.nix     # Yazi, fzf
│   └── utils.nix             # Git, 시스템 유틸리티
│
└── virtualization.nix        # KVM/QEMU, Podman
```

## NixOS 모듈 상세

### boot.nix

부트로더 및 커널 설정

| 설정      | 값                           |
| --------- | ---------------------------- |
| 부트로더  | systemd-boot                 |
| IOMMU     | Intel/AMD 활성화             |
| KVM 모듈  | kvm-intel 또는 kvm-amd       |
| 추가 모듈 | vfio-pci (GPU passthrough용) |

### locale.nix

로케일 및 타임존 설정

| 설정      | 값          |
| --------- | ----------- |
| 타임존    | Asia/Seoul  |
| 로케일    | en_US.UTF-8 |
| 콘솔 키맵 | us          |

### network.nix

네트워크 아키텍처 (systemd-networkd 기반)

**주요 컴포넌트:**

- `enp1s0`: 물리 NIC (브릿지 슬레이브)
- `vmbr0`: VLAN trunk 브릿지
- `vlan10`: Management VLAN 인터페이스
- `vlan20`: Services VLAN 인터페이스
- `vm-*`: VM별 TAP 인터페이스

**기능:**

- VLAN 필터링 (bridge vlan)
- NAT (iptables masquerade)
- IPv4 포워딩
- 방화벽 규칙

### ssh.nix

SSH 서버 설정

| 설정          | 값            |
| ------------- | ------------- |
| 포트          | 22            |
| 루트 로그인   | 허용 (개발용) |
| 패스워드 인증 | 비활성화      |
| 공개키 인증   | 활성화        |

### sops.nix

시크릿 관리 설정

| 설정        | 경로                          |
| ----------- | ----------------------------- |
| 시크릿 파일 | secrets/secrets.yaml          |
| age 키 경로 | /etc/ssh/ssh_host_ed25519_key |

**관리되는 시크릿:**

- `users/rootPassword`
- `users/limjihoonPassword`

### nix-settings.nix

Nix 데몬 설정

| 설정        | 값                  |
| ----------- | ------------------- |
| 실험적 기능 | nix-command, flakes |
| 자동 GC     | 매주, 7일 이상 삭제 |
| 자동 최적화 | 활성화              |

### users.nix

사용자 계정 관리

| 사용자    | UID  | 그룹              | 셸  |
| --------- | ---- | ----------------- | --- |
| root      | 0    | root              | zsh |
| limjihoon | 1000 | users, wheel, kvm | zsh |

**특징:**

- `mutableUsers = false` (NixOS가 계정 관리)
- sops-nix로 패스워드 주입
- SSH 공개키 파일에서 로드

### microvm-storage.nix

MicroVM 스토리지 디렉토리 설정

생성되는 디렉토리:

- `/var/lib/microvms/vault/data`
- `/var/lib/microvms/jenkins/home`
- `/var/lib/microvms/registry/data`
- `/var/lib/microvms/k8s-master/etcd`

## Home-manager 모듈 상세

### shell.nix

Zsh 셸 설정

**Oh-My-Zsh 플러그인:**

- git
- kubectl
- kube-ps1
- zsh-autosuggestions
- zsh-syntax-highlighting

**테마:** Powerlevel10k (Instant Prompt)

**별칭 (발췌):**

```bash
# Kubernetes
k=kubectl
kgp=kubectl get pods
kgs=kubectl get svc

# Git
gs=git status
gc=git commit
gp=git push

# 시스템
ll=ls -la
..=cd ..
```

**커스텀 함수:**

- `kube-manifest`: K8s 리소스 YAML 출력
- `gitlog`: 그래프형 git 로그
- `pslog`: 프로세스 로그 검색
- `systemdlog`: systemd 유닛 로그
- `search`: 파일 검색 (fd + fzf)

### editor.nix

Neovim 설정

| 설정                | 값                    |
| ------------------- | --------------------- |
| 플러그인 프레임워크 | LazyVim               |
| 별칭                | vim → nvim, vi → nvim |

### file-explorer.nix

파일 탐색 도구

**Yazi:**

- 터미널 파일 매니저
- 커스텀 테마 적용

**fzf:**

- 퍼지 파인더
- 커스텀 스타일 (border, padding)

### utils.nix

시스템 유틸리티 및 Git 설정

**Git 설정:**

- user.name: limjihoon
- user.email: lonelynight1026@gmail.com

**설치되는 패키지:**

- 검색: ripgrep, fd
- 모니터링: htop, btop, ncdu
- 파일: bat, eza, jq, yq
- 네트워크: curl, wget, tcpdump, nftables
- 기타: bridge-utils, tree, unzip

## virtualization.nix

가상화 설정

### KVM/QEMU

| 설정         | 값                           |
| ------------ | ---------------------------- |
| 하이퍼바이저 | QEMU                         |
| UEFI 펌웨어  | OVMF                         |
| libvirt      | 비활성화 (MicroVM 직접 사용) |

### Podman

| 설정             | 값     |
| ---------------- | ------ |
| Docker 호환 소켓 | 활성화 |
| 자동 프룬        | 매주   |

## 모듈 추가 가이드

### 새 NixOS 모듈 추가

1. `modules/nixos/` 디렉토리에 파일 생성
2. `configuration.nix`에서 import

```nix
# modules/nixos/my-module.nix
{ config, pkgs, ... }: {
  # 설정 내용
}

# configuration.nix
imports = [
  ./modules/nixos/my-module.nix
];
```

### 새 Home-manager 모듈 추가

1. `modules/home-manager/` 디렉토리에 파일 생성
2. `home.nix`에서 import

```nix
# modules/home-manager/my-module.nix
{ config, pkgs, ... }: {
  # 사용자 설정 내용
}

# home.nix
imports = [
  ./modules/home-manager/my-module.nix
];
```

## 의존성 관계

```
configuration.nix
├── modules/nixos/boot.nix
├── modules/nixos/locale.nix
├── modules/nixos/network.nix      ← lib/homelab-constants.nix 참조
├── modules/nixos/ssh.nix
├── modules/nixos/sops.nix         ← secrets/secrets.yaml 참조
├── modules/nixos/nix-settings.nix
├── modules/nixos/users.nix        ← sops secrets 참조
├── modules/nixos/microvm-storage.nix
└── modules/virtualization.nix

home.nix
├── modules/home-manager/shell.nix
├── modules/home-manager/editor.nix
├── modules/home-manager/file-explorer.nix
└── modules/home-manager/utils.nix
```
