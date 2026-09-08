# ADR 0008: CI/CD와 이미지 배포

## 상태

채택.

## 맥락

현재 `.github/workflows/README.md`는 GitHub Actions가 이 repo의 실행 경로가 아니라고
명시한다. 이전 workflow는 `.github/workflows.disabled/` 아래에 보존되어 있다.

현재 목표:

- 홈랩 내부 변경은 사용자가 직접 이해하고 실행한다.
- 앱 이미지는 digest pin을 목표로 한다.
- Flux는 Git에 기록된 Kubernetes 상태를 클러스터에 수렴시킨다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| 로컬 only | `just check`, `just plan`, `just apply`를 사용자가 실행 | 통제감 최고, secret 노출면 작음 | 자동화 부족 |
| GitHub Actions CI | PR/push에서 check 실행 | 회귀 방지 | secret, Nix cache, private repo 접근 관리 필요 |
| GitHub Actions CD | push 후 deploy/reconcile 실행 | 자동 배포 | 홈랩 접근권한과 실패 복구 경로 복잡 |
| 내부 runner | 홈랩 안에서 CI/CD 실행 | 네트워크 접근 쉬움 | runner 운영과 권한 관리 필요 |
| Flux Image Automation | image tag/digest 변경 PR 자동화 | GitOps 친화적 | image policy 학습/운영 복잡도 증가 |

## 결정

현재는 `로컬 검증 + GitOps reconcile`을 유지한다. 원격 CI/CD는 보류한다.

## 근거

- 현재 병목은 자동화 부족이 아니라 구성 이해 부족이다.
- 원격 CD는 홈랩 SSH, kubeconfig, registry credential을 CI에 위임해야 한다.
- 단일 사용자 홈랩에서는 사용자가 `just plan` 결과를 보고 `CONFIRM_DEPLOY=homelab`로 적용하는 흐름이 더 안전하다.
- Flux는 cluster 내부에서 Git 상태를 수렴하므로, CI가 직접 cluster mutation을 수행하지 않아도 된다.
- image digest pin은 자동화보다 먼저 지켜야 할 배포 contract다.

## 운영 명세

- PR/commit 전 로컬에서 `just check`를 실행한다.
- 인프라 변경은 `just plan infra ...` 후 `CONFIRM_DEPLOY=homelab just apply infra ...`로 적용한다.
- GitOps 변경은 `just plan gitops` 후 `CONFIRM_DEPLOY=homelab just apply gitops`로 적용한다.
- 앱 이미지는 registry push 후 manifest의 digest를 갱신한다.
- CI/CD가 cluster credential을 소유하지 않는다.

## 확장 전략

| 상황 | 선택 |
| --- | --- |
| 개인 실험 | 로컬 only |
| 변경 빈도 증가 | GitHub Actions CI 복구 |
| 외부 기여/PR 증가 | CI 필수화 |
| 반복 배포 증가 | 내부 runner 또는 Flux Image Automation 검토 |
| 무인 배포 필요 | CD 권한 범위 ADR 작성 후 도입 |

## 재검토 조건

- `just check` 누락으로 main branch 회귀가 발생한다.
- 앱 image digest 갱신이 반복 작업으로 굳어진다.
- 외부 contributor 또는 여러 장비에서 동일 검증이 필요해진다.
- 내부 runner를 격리할 수 있는 별도 namespace/VM이 준비된다.

## 근거 자료

- 로컬: `.github/workflows/README.md`, `.github/workflows.disabled/`, `justfile`, `deploy/k8s/clusters/homelab`
- GitHub Actions workflows: https://docs.github.com/en/actions/concepts/workflows-and-actions/workflows
- Flux concepts: https://fluxcd.io/flux/concepts/
- Kubernetes images: https://kubernetes.io/docs/concepts/containers/images/
