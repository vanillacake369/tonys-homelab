# secrets/ - 로컬 시크릿 작업 공간

이 디렉토리는 로컬 배포에 필요한 시크릿과 공개키를 생성해 두는 작업
공간입니다. 저장소에는 실제 값이 들어간 파일을 커밋하지 않고, 예제와
운영 절차만 커밋합니다.

## 디렉토리 구조

```
secrets/
├── secrets.yaml          # 실제 시크릿 입력/편집 파일 (Git 미추적)
├── secrets.example.yaml  # 커밋 가능한 예제 템플릿이 필요할 때만 추가
├── limjihoon.pub         # 로컬 개발 머신 SSH 공개키 (Git 미추적)
├── homelab-1.pub         # 물리 호스트 SSH 공개키 (Git 미추적)
└── README.md             # 이 문서
```

커밋 가능한 파일은 `README.md`, `*.example.*`, 공개 설정 파일로 검토된
파일만 허용합니다. 실제 값, 암호화된 secret payload, host/user 공개키,
kubeconfig, private key는 커밋하지 않습니다.

## 원칙

이 저장소에는 재현 가능한 구조와 검토 가능한 예제만 남깁니다. 특정
환경에서만 의미가 있는 값, 배포 시점에 생성되는 값, 접근 권한을 넓힐
수 있는 값은 로컬 작업 공간이나 외부 secret store에 둡니다.

암호화 여부만으로 커밋 가능성을 판단하지 않습니다. 파일 이름, 위치,
소유자, 회전 절차, 복구 경로까지 검토했을 때 공개 저장소에 남아도 되는
정보만 커밋합니다.

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

## sops-nix 시크릿

### 작동 방식

1. 로컬에서 `sops` CLI로 실제 값을 만들거나 편집합니다.
2. 배포 시 호스트의 복호화 키로 필요한 위치에만 값을 제공합니다.
3. NixOS는 복호화된 값을 `/run/secrets/`에 마운트합니다.

### 시크릿 편집

```bash
# sops로 열면 자동 복호화/암호화
sops secrets/secrets.yaml
```

### 주의사항

- `secrets.yaml`, `secret.enc.yaml`, `setup-secret.enc.yaml` 같은 실제
  secret payload는 Git에 커밋하지 않습니다.
- `*.example.yaml`은 placeholder만 담은 템플릿일 때 커밋할 수 있습니다.
- age 개인키, SSH private key, kubeconfig, token, password 파일은 절대
  커밋하지 않습니다.
- `.sops.yaml`은 공개키/규칙만 포함하는 설정 파일로 검토 후 커밋할 수
  있습니다.
