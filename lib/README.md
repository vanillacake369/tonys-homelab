# lib/ - Domain-Driven Architecture

홈랩 인프라의 **Single Source of Truth**입니다.

## 구조

```
lib/
├── domains/                    # 순수 데이터 (WHAT)
│   ├── shell.nix               # 쉘 별칭, 함수, zsh 설정
│   ├── packages.nix            # 패키지 그룹 및 프로파일
│   ├── editor.nix              # 에디터 설정
│   ├── users.nix               # 사용자 정보
│   ├── network.nix             # 네트워크 토폴로지
│   ├── vms.nix                 # VM 정의
│   └── hosts.nix               # 호스트 정의
│
├── adapters/                   # 변환 로직 (HOW)
│   ├── nixos.nix               # Domain → NixOS options
│   ├── home-manager.nix        # Domain → home-manager options
│   ├── microvms.nix            # Domain → MicroVM 생성
│   ├── colmena.nix             # Domain → Colmena hive
│   ├── home-manager-module.nix # NixOS home-manager 모듈 래퍼
│   └── special-args.nix        # specialArgs 생성
│
├── profiles.nix                # 프로파일 접근 API
└── homelab-constants.nix       # 하위 호환성 (deprecated)
```

## 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│                    lib/domains/                         │
│  (순수 데이터: shell, packages, editor, vms, hosts...)  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    lib/adapters/                        │
│  nixos.nix │ home-manager.nix │ microvms.nix │ colmena │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              NixOS / Home-manager / VMs                 │
└─────────────────────────────────────────────────────────┘
```

**장점:**
- 데이터(WHAT)와 로직(HOW) 분리
- 모듈 중첩 깊이 최대 3
- 설정 중복 제거
- VM별 프로파일 자동 적용

## Adapters 역할

| Adapter | 역할 |
|---------|------|
| `nixos.nix` | 프로파일 → NixOS 시스템 설정 |
| `home-manager.nix` | 프로파일 → home-manager 사용자 설정 |
| `microvms.nix` | VM 정의 → MicroVM 모듈 생성 |
| `colmena.nix` | 호스트/VM 정의 → Colmena hive |
| `special-args.nix` | 환경변수 → specialArgs |
| `home-manager-module.nix` | NixOS 내 home-manager 통합 |

## 프로파일 시스템

```nix
# packages.nix의 프로파일
profiles = {
  minimal  = ["core" "shell"];
  server   = ["core" "shell" "editor" "network" "monitoring" "dev" "hardware"];
  k8s-node = ["core" "shell" "editor" "network" "monitoring" "k8s" "hardware"];
  dev      = ["core" "shell" "editor" "network" "monitoring" "dev" "k8s" "terminal"];
  full     = [/* 전체 */];
};
```

## 사용법

### flake.nix에서

```nix
profiles = import ./lib/profiles.nix { inherit pkgs lib; };

# NixOS 설정
profiles.nixos.server.all

# Home-manager 설정
profiles.homeManager.dev.all

# 도메인 직접 접근
profiles.domains.shell.aliases
```

### VM 프로파일 자동 적용

`adapters/microvms.nix`가 VM 이름에 따라 프로파일 자동 선택:
- `k8s-*` → `k8s-node` 프로파일
- 기타 → `server` 프로파일
