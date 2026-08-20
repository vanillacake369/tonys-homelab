# secrets/ - 암호화된 시크릿 & 공개키

sops-nix를 사용한 시크릿 관리 및 인프라 접근을 위한 공개키 관리입니다.

## 디렉토리 구조

```
secrets/
├── secrets.yaml          # 암호화된 시크릿 (Git 추적)
├── limjihoon.pub         # 로컬 개발 머신 SSH 공개키 (Git 미추적)
├── homelab-1.pub         # 물리 호스트 SSH 공개키 (Git 미추적)
└── README.md             # 이 문서
```

## SSH 공개키 관리

인프라(물리 호스트 및 VM) 접근을 위한 공개키는 `atoms/system/authorized-keys.nix`에서 자동으로 읽어와 설정됩니다.

### 1. 로컬 개발 머신 키 등록
로컬에서 Colmena 배포를 수행하기 위해 필요합니다.
```bash
cat ~/.ssh/id_ed25519.pub > secrets/limjihoon.pub
```

### 2. 물리 호스트 키 등록
물리 호스트에서 VM에 직접 접속하거나, Ansible 배포 시 필요합니다.
```bash
ssh homelab-1 "cat ~/.ssh/id_ed25519.pub" > secrets/homelab-1.pub
```

> **주의:** 공개 저장소에서는 인프라 공개키도 접근 표면 정보가 될 수 있어 Git에 올리지 않습니다.
> 로컬 배포 전 필요한 공개키 파일을 `secrets/`에 직접 생성하세요.

---

## sops-nix (암호화 시크릿)

### 작동 방식
1. **로컬**: `sops` CLI로 `secrets.yaml` 편집 (자동 암호화/복호화)
2. **서버**: 호스트의 SSH Key를 통해 배포 시 자동 복호화
3. **NixOS**: 복호화된 값을 `/run/secrets/`에 마운트

### 시크릿 편집
```bash
# sops로 열면 자동 복호화/암호화
sops secrets/secrets.yaml
```

### 주의사항
- **secrets.yaml**: Git에 커밋 가능 (암호화됨)
- **age 개인키**: 절대 커밋하지 않음
- **.sops.yaml**: 공개키 정보만 포함하므로 커밋 가능
