# GitHub Workflows

## 개요
- 이 디렉터리는 CI/CD 및 품질 검사용 GitHub Actions 워크플로를 관리합니다.
- 주요 워크플로: `ci-cd.yml`, `ci-common.yml`, `deadnix.yml`, `flake-update.yml`, `security.yml`, `typos.yml`.

## 시크릿 목록
- `GIT_CRYPT_KEY`: git-crypt 복호화용 키 (Base64).
- `SOPS_AGE_KEY`: sops-nix에서 사용하는 age 키.
- `TS_OAUTH_CLIENT_ID`: Tailscale OAuth client id.
- `TS_OAUTH_SECRET`: Tailscale OAuth secret.
- `TS_DEST_IP`: 배포 대상 Tailscale IP (예: homelab).
- `SSH_HOST_KEY`: 대상 호스트의 SSH host public key (`/etc/ssh/ssh_host_ed25519_key.pub`).
- `SSH_PUB_KEY`: Colmena 실행 시 전달되는 사용자 공개키.
- `GITHUB_TOKEN`: GitHub 기본 토큰 (자동 제공, 별도 등록 불필요).

## 배포 흐름
1. `ci-cd.yml`의 `ci` 잡이 실행되어 flake 체크 및 dry-run 빌드 수행.
2. main 브랜치 push일 경우 `cd` 잡이 실행되어 Tailscale 연결 후 Colmena 배포.
3. `ci-common.yml`은 CI/CD 공통 단계를 재사용하는 reusable workflow.

## 워크플로 설명 및 주의사항

### CI/CD (`.github/workflows/ci-cd.yml`)
- Nix 관련 변경 시 CI 실행, main push 시 CD 실행.
- `cd`는 `TS_DEST_IP`와 `SSH_HOST_KEY`로 known_hosts를 구성하여 호스트 검증 수행.
- `SSH_HOST_KEY`는 반드시 host key여야 하며 사용자 키로 대체하면 안 됩니다.

### Common Steps (`.github/workflows/ci-common.yml`)
- `mode=ci`와 `mode=cd`로 분기되며 공통 단계(Checkout, Nix 설치, 캐시 등) 재사용.
- 액션 버전은 태그로 고정되어 있으며 업데이트는 수동 관리.

### Deadnix (`.github/workflows/deadnix.yml`)
- Nix 파일 변경 시 dead code 검사.
- `GIT_CRYPT_KEY`로 복호화 필요.

### Flake Update (`.github/workflows/flake-update.yml`)
- 주기적으로 `flake.lock` 업데이트 PR 생성.
- `contents: write`, `pull-requests: write` 권한 필요.

### Security (`.github/workflows/security.yml`)
- Gitleaks로 시크릿 유출 검사.
- Flake inputs 헬스 체크 실행.

### Typos (`.github/workflows/typos.yml`)
- `.typos.toml` 설정 기반 스펠 체크.
- 사전 커스텀 시 `.typos.toml` 업데이트 필요.
