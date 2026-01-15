# tonys-homelab

NixOS 기반 홈랩 서버 설정 (Proxmox 대체)

## 개요

물리 서버에 NixOS를 설치하고 선언적으로 관리하는 설정입니다.

**주요 기능**
- 선언적 인프라 관리 (Nix Flakes)
- LVM thin provisioning (SSD 최적화)
- sops-nix 암호화
- KVM/QEMU 가상화
- Podman 컨테이너

## 빠른 시작

### 1. Secrets 설정

```bash
# SSH 공개키 저장
mkdir -p secrets
cat > secrets/ssh-public-key.txt << EOF
ssh-rsa AAAAB3... your-key
EOF

# .sops.yaml에 age 키 설정 (서버 키 필요)
ssh homelab "cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age"
```

### 2. 배포

```bash
# 초기 설치 (데이터 삭제 주의!)
just deploy 192.168.45.82

# 시스템 업데이트
just update 192.168.45.82
```

## 프로젝트 구조

```
tonys-homelab/
├── flake.nix              # Nix flake 설정
├── configuration.nix      # 메인 시스템 설정
├── disko-config.nix       # 디스크 파티셔닝
├── justfile               # 배포 자동화
├── .sops.yaml             # Secrets 암호화 설정
│
├── modules/               # NixOS 모듈
│   ├── boot.nix          # 부트로더, IOMMU
│   ├── locale.nix        # 타임존, 로케일
│   ├── network.nix       # 네트워크, SSH
│   ├── nix-settings.nix  # Nix 데몬
│   ├── users.nix         # 사용자 계정
│   └── virtualization.nix # KVM, Podman
│
└── secrets/              # 비밀 정보 (gitignore)
    ├── secrets.yaml      # 암호화된 패스워드
    └── ssh-public-key.txt # SSH 공개키
```

## 디스크 구성

| 파티션 | 크기 | 용도 |
|--------|------|------|
| ESP | 1G | EFI 부트 |
| Swap | 16G | 스왑 (암호화) |
| root | 200G | NixOS 시스템 |
| vm_thinpool | 380G (물리)<br>800G (논리) | VM 스토리지 |
| data_thinpool | 300G (물리)<br>600G (논리) | 애플리케이션 데이터 |
| vault | 20G | 보안 스토리지 |

**필요 디스크:** 최소 920GB

## 주요 명령어

```bash
# 배포
just test              # VM에서 테스트
just deploy <IP>       # 초기 설치
just update <IP>       # 원격 업데이트
just build <IP>        # 빌드만 (dry-run)

# 검증
just check             # Flake 검증
just upgrade           # Flake 업데이트
just fmt               # 코드 포맷팅

# Secrets
just secrets-edit      # Secrets 편집
just secrets-show      # Secrets 확인
just age-key <IP>      # Age 키 가져오기

# 유틸리티
just status <IP>       # 시스템 상태
just clean <IP>        # 세대 정리
just ssh <IP>          # SSH 접속
```

## Secrets 관리

sops-nix를 사용한 패스워드 암호화:

```bash
# 1. 서버의 age 키 가져오기
just age-key 192.168.45.82

# 2. .sops.yaml 업데이트
# 3. Secrets 편집
just secrets-edit

# 4. 배포 (자동 복호화)
just update 192.168.45.82
```

**보안 모델**
- 패스워드: sops로 암호화 (Git 커밋 가능)
- SSH 공개키: `secrets/`에 저장 (gitignore)
- SSH 개인키: 저장 안 함
- mutableUsers: false (NixOS가 관리)

## 설정 변경

### SSH 공개키

`secrets/ssh-public-key.txt` 편집

### 패스워드

```bash
# 해시 생성
ssh homelab "mkpasswd -m sha-512"

# secrets.yaml 편집
just secrets-edit
```

### 방화벽

`modules/network.nix` 수정:

```nix
allowedTCPPorts = [ 22 80 443 ];
```

## 문서

- [NIXOS_ANYWHERE_GUIDE.md](./NIXOS_ANYWHERE_GUIDE.md) - 상세 설치 가이드
- [modules/](./modules/) - 모듈별 설명
- [disko-config.nix](./disko-config.nix) - 스토리지 구조

## 참고

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [disko](https://github.com/nix-community/disko)
- [sops-nix](https://github.com/Mic92/sops-nix)
