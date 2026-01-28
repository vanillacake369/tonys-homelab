# Phase 0: Domain-Driven Architecture Migration

## 목표

현재 계층적 구조를 **Flat한 도메인 중심 구조**로 마이그레이션하여:
1. 무한 depth 문제 해결
2. home-manager/NixOS 간 설정 공유
3. VM에 경량 설정 적용 가능

## 현재 구조 (문제)

```
flake.nix
├── homelab-constants.nix (모든 것이 한 파일에)
├── modules/nixos/ (NixOS 전용)
├── modules/home-manager/ (HM 전용, 중복 설정)
└── lib/mk-microvms.nix (또 다른 중복)
```

**문제점:**
- `homelab-constants.nix`가 너무 큼 (네트워크 + VM + 호스트 + 공통설정)
- home-manager와 nixos 모듈 간 aliases, packages 중복
- 계층이 깊어지면 무한 depth 발생

## 목표 구조

```
lib/
├── domains/                      # 순수 데이터 (의존성 없음)
│   ├── network.nix              # 네트워크 토폴로지
│   ├── vms.nix                  # VM 정의
│   ├── hosts.nix                # 물리 호스트 정의
│   ├── shell.nix                # 쉘 설정 (aliases, functions)
│   ├── packages.nix             # 패키지 그룹 정의
│   ├── editor.nix               # 에디터 설정
│   └── users.nix                # 사용자 정보
│
├── profiles.nix                  # 도메인 조합 프로파일
│
└── adapters/                     # 도메인 → 플랫폼 변환
    ├── nixos.nix                # 도메인 → NixOS options
    └── home-manager.nix         # 도메인 → HM options
```

## 의존성 흐름

```
         domains (순수 데이터)
        ┌───┬───┬───┬───┬───┐
        │net│vm │shell│pkg│usr│
        └─┬─┴─┬─┴──┬──┴─┬─┴─┬─┘
          │   │    │    │   │
          ▼   ▼    ▼    ▼   ▼
    ┌─────────────────────────────┐
    │         flake.nix           │ (조합 및 주입)
    └──────┬─────────────┬────────┘
           │             │
           ▼             ▼
    ┌──────────┐   ┌────────────┐
    │ adapters/│   │ adapters/  │
    │ nixos    │   │ home-mgr   │
    └────┬─────┘   └─────┬──────┘
         │               │
         ▼               ▼
    ┌─────────┐    ┌───────────┐
    │ modules/│    │ modules/  │
    │ nixos   │    │ home-mgr  │
    └─────────┘    └───────────┘

Depth = 최대 3 (domain → flake → adapter/module)
```

## 세부 계획

### Phase 0.1: lib/domains/ 구조 생성

```bash
mkdir -p lib/domains lib/adapters
```

빈 도메인 파일들 생성:
- `lib/domains/network.nix`
- `lib/domains/vms.nix`
- `lib/domains/hosts.nix`
- `lib/domains/shell.nix`
- `lib/domains/packages.nix`
- `lib/domains/editor.nix`
- `lib/domains/users.nix`

### Phase 0.2: homelab-constants.nix 분리

**Before:** `lib/homelab-constants.nix` (250줄)

**After:**
- `lib/domains/network.nix` - networks, vlans, dns
- `lib/domains/vms.nix` - vms 정의
- `lib/domains/hosts.nix` - hosts 정의, common 설정

호환성을 위해 `homelab-constants.nix`는 domains를 re-export:
```nix
# lib/homelab-constants.nix (하위 호환)
let
  network = import ./domains/network.nix;
  vms = import ./domains/vms.nix;
  hosts = import ./domains/hosts.nix;
in {
  inherit (network) networks;
  inherit (vms) vms vmOrder microvmList vmTagList k8s;
  inherit (hosts) hosts defaultHost common;
}
```

### Phase 0.3: 사용자 환경 도메인 생성

`modules/home-manager/`에서 데이터 추출:

**lib/domains/shell.nix:**
```nix
{
  aliases = {
    ll = "ls -l";
    cat = "bat --style=plain --paging=never";
    grep = "rg";
    k = "kubectl";
    # ...
  };

  functions = {
    kube-manifest = ''...'';
    gitlog = ''...'';
    # ...
  };

  zsh = {
    ohMyZsh.plugins = ["git" "kubectl" "kube-ps1"];
  };
}
```

**lib/domains/packages.nix:**
```nix
{
  groups = {
    core = p: with p; [coreutils findutils];
    shell = p: with p; [bat ripgrep fzf jq];
    editor = p: with p; [neovim vim];
    network = p: with p; [curl wget bind tcpdump];
    k8s = p: with p; [kubectl];
    dev = p: with p; [git htop btop strace];
    gpu-amd = p: with p; [amdgpu_top];
  };
}
```

### Phase 0.4: 어댑터 생성

**lib/adapters/nixos.nix:**
```nix
{ domains, pkgs, profile ? "server" }: {
  shell = { ... };      # domains.shell → programs.zsh
  packages = { ... };   # domains.packages → environment.systemPackages
  editor = { ... };     # domains.editor → programs.neovim
}
```

**lib/adapters/home-manager.nix:**
```nix
{ domains, pkgs, profile ? "full" }: {
  shell = { ... };      # domains.shell → programs.zsh + oh-my-zsh
  packages = { ... };   # domains.packages → home.packages
  editor = { ... };     # domains.editor → programs.neovim
}
```

### Phase 0.5: 프로파일 정의

**lib/profiles.nix:**
```nix
{
  minimal = {
    packages = ["core" "shell"];
    features = ["shell"];
  };

  server = {
    packages = ["core" "shell" "editor" "network"];
    features = ["shell" "editor"];
  };

  k8s-node = {
    packages = ["core" "shell" "editor" "network" "k8s"];
    features = ["shell" "editor"];
  };

  dev = {
    packages = ["core" "shell" "editor" "network" "k8s" "dev"];
    features = ["shell" "editor"];
  };

  full = {
    packages = ["core" "shell" "editor" "network" "k8s" "dev" "gpu-amd"];
    features = ["shell" "editor"];
    zsh.ohMyZsh = true;
    zsh.powerlevel10k = true;
  };
}
```

### Phase 0.6: flake.nix 수정

```nix
let
  domains = {
    network = import ./lib/domains/network.nix;
    vms = import ./lib/domains/vms.nix;
    hosts = import ./lib/domains/hosts.nix;
    shell = import ./lib/domains/shell.nix;
    packages = import ./lib/domains/packages.nix;
    editor = import ./lib/domains/editor.nix;
    users = import ./lib/domains/users.nix;
  };
  profiles = import ./lib/profiles.nix;
in {
  nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit domains profiles;
      # 하위 호환
      homelabConstants = import ./lib/homelab-constants.nix;
    };
  };
}
```

### Phase 0.7: mk-microvms.nix 마이그레이션

`mkVmCommonModule`을 어댑터 기반으로 변경:
```nix
mkVmCommonModule = { domains, profile ? "server" }:
  let adapter = import ../adapters/nixos.nix { inherit domains pkgs profile; };
  in {
    imports = [ adapter.shell adapter.packages adapter.editor ];
  };
```

### Phase 0.8: home-manager 모듈 마이그레이션

`modules/home-manager/*.nix`를 어댑터 사용으로 변경:
```nix
# modules/home-manager/shell.nix
{ domains, ... }:
let adapter = import ../../lib/adapters/home-manager.nix { inherit domains pkgs; };
in adapter.shell
```

### Phase 0.9: 테스트

```bash
# 빌드 테스트
just check

# 호스트 배포 테스트
just deploy

# VM 테스트
ssh root@10.0.20.10  # k8s-master
```

## 마이그레이션 전략

1. **점진적 마이그레이션** - 한 도메인씩 이동
2. **하위 호환 유지** - `homelabConstants` re-export
3. **테스트 우선** - 각 단계마다 `just check`

## 예상 결과

| 항목 | Before | After |
|------|--------|-------|
| 최대 Depth | 무한 가능 | 3 고정 |
| 설정 중복 | HM/NixOS 별도 | 도메인 1개 |
| VM 설정 크기 | 고정 | 프로파일로 조절 |
| 새 플랫폼 추가 | 전체 복사 | 어댑터만 작성 |

## 완료 조건

- [ ] `just check` 통과
- [ ] `just deploy` 성공
- [ ] VM들 정상 부팅
- [ ] K8s 클러스터 정상 동작
- [ ] home-manager 설정 정상 적용
