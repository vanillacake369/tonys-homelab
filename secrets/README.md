# secrets/ - 암호화된 시크릿

sops-nix를 사용한 시크릿 관리입니다.

## 디렉토리 구조

```
secrets/
├── secrets.yaml          # 암호화된 시크릿 (Git 추적)
├── ssh-public-key.txt    # SSH 공개키 (Git 무시)
└── README.md             # 이 문서
```

## sops-nix 개요

### 작동 방식

1. **로컬**: `sops` CLI로 secrets.yaml 편집 (자동 암호화/복호화)
2. **서버**: age 키로 배포 시 자동 복호화
3. **NixOS**: 복호화된 값을 `/run/secrets/`에 마운트

### 암호화 키

| 키 타입        | 용도        | 위치                            |
| -------------- | ----------- | ------------------------------- |
| age (SSH 기반) | 서버 복호화 | `/etc/ssh/ssh_host_ed25519_key` |
| age (개인)     | 로컬 편집   | `.sops.yaml`에 정의             |

## 설정 방법

### 1. 서버 age 키 확인

```bash
# 서버의 SSH 호스트 키를 age 공개키로 변환
ssh homelab "cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age"
# 출력: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 2. .sops.yaml 설정

프로젝트 루트에 `.sops.yaml` 생성:

```yaml
keys:
  # 서버 age 키 (SSH 호스트 키 기반)
  - &server age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  # 개인 age 키 (선택사항)
  - &personal age1yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy

creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
          - *server
          - *personal
```

### 3. 시크릿 파일 생성/편집

```bash
# 새 파일 생성
sops secrets/secrets.yaml

# 기존 파일 편집
sops secrets/secrets.yaml

# 편집기에서 저장하면 자동 암호화
```

### 4. NixOS 설정

`modules/nixos/sops.nix`:

```nix
{ config, ... }: {
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    secrets = {
      "users/rootPassword" = {
        neededForUsers = true;
      };
      "users/limjihoonPassword" = {
        neededForUsers = true;
      };
    };
  };
}
```

## secrets.yaml 구조

```yaml
users:
  rootPassword: ENC[AES256_GCM,data:...,type:str]
  limjihoonPassword: ENC[AES256_GCM,data:...,type:str]
sops:
  # 메타데이터 (자동 생성)
  kms: []
  gcp_kms: []
  azure_kv: []
  hc_vault: []
  age:
    - recipient: age1xxx...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2024-..."
  mac: ENC[AES256_GCM,data:...,type:str]
  pgp: []
  unencrypted_suffix: _unencrypted
  version: 3.9.0
```

## 주요 작업

### 패스워드 해시 생성

```bash
# 서버에서 실행
ssh homelab "mkpasswd -m sha-512"
# 프롬프트에 패스워드 입력
# 출력된 해시를 secrets.yaml에 저장
```

### 시크릿 편집

```bash
# sops로 열면 자동 복호화
sops secrets/secrets.yaml

# 편집기에서 수정 후 저장
# 저장 시 자동 암호화
```

### 시크릿 확인 (복호화)

```bash
# 전체 내용 확인
sops -d secrets/secrets.yaml

# 특정 키 확인
sops -d --extract '["users"]["rootPassword"]' secrets/secrets.yaml
```

### 새 시크릿 추가

1. secrets.yaml 편집:

```yaml
users:
  rootPassword: $6$...
  limjihoonPassword: $6$...
myapp:
  apiKey: my-secret-api-key # 새 시크릿
```

2. sops.nix에 선언:

```nix
sops.secrets."myapp/apiKey" = {
  owner = "myapp";
  group = "myapp";
  mode = "0400";
};
```

3. 서비스에서 사용:

```nix
services.myapp = {
  enable = true;
  environmentFile = config.sops.secrets."myapp/apiKey".path;
};
```

## 키 로테이션

### 서버 SSH 키 변경 시

1. 새 서버 age 키 확인:

```bash
ssh homelab "cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age"
```

2. `.sops.yaml` 업데이트:

```yaml
keys:
  - &server age1<새키>
```

3. 시크릿 재암호화:

```bash
# 기존 키로 복호화 후 새 키로 암호화
sops updatekeys secrets/secrets.yaml
```

### age 키 추가/제거

1. `.sops.yaml` 수정
2. 키 업데이트 실행:

```bash
sops updatekeys secrets/secrets.yaml
```

## 주의사항

### 보안

- **secrets.yaml**: Git에 커밋 가능 (암호화됨)
- **ssh-public-key.txt**: `.gitignore`에 추가 권장
- **age 개인키**: 절대 커밋하지 않음
- **.sops.yaml**: 공개키만 포함, 커밋 가능

### 일반적인 실수

1. **sops 없이 편집**: 암호화 깨짐 - 항상 `sops` 명령어 사용

2. **키 불일치**: `.sops.yaml`의 키와 서버 키가 다르면 복호화 실패

   ```bash
   # 키 확인
   sops -d secrets/secrets.yaml  # 로컬 테스트
   ```

3. **neededForUsers 누락**: 사용자 패스워드는 이 옵션 필수
   ```nix
   sops.secrets."users/rootPassword" = {
     neededForUsers = true;  # 필수!
   };
   ```

### 트러블슈팅

**"failed to decrypt"**

- `.sops.yaml`의 age 키가 올바른지 확인
- 로컬 age 키가 `.sops.yaml`에 등록되어 있는지 확인

**배포 시 복호화 실패**

- 서버의 SSH 호스트 키 변경 여부 확인
- `sops updatekeys`로 재암호화

**권한 오류**

- `/run/secrets/` 파일 권한 확인
- `sops.secrets.<name>.mode` 설정 확인

## 파일 목록

### secrets.yaml

암호화된 시크릿 저장

**현재 저장된 시크릿:**

- `users/rootPassword` - root 사용자 패스워드 해시
- `users/limjihoonPassword` - limjihoon 사용자 패스워드 해시

### ssh-public-key.txt

SSH 공개키 저장 (평문)

**용도:**

- NixOS 사용자 authorized_keys 설정
- `modules/nixos/users.nix`에서 참조

**설정 방법:**

```bash
cat ~/.ssh/your-key.pub > secrets/ssh-public-key.txt
```

## 참고 자료

- [sops-nix GitHub](https://github.com/Mic92/sops-nix)
- [sops GitHub](https://github.com/getsops/sops)
- [age 암호화](https://github.com/FiloSottile/age)
