# k8s/ — FluxCD GitOps

이 디렉토리는 FluxCD를 통해 Kubernetes 클러스터 상태를 Git과 자동 동기화하는 GitOps 구성입니다.

## FluxCD란?

FluxCD는 Git 리포지토리를 Single Source of Truth로 사용하는 GitOps 오퍼레이터입니다.
Git에 커밋하면 클러스터가 자동으로 해당 상태로 수렴(reconcile)합니다.

### 핵심 개념

| 개념 | 설명 |
|---|---|
| **GitRepository** | Flux가 모니터링하는 Git 소스 (이 repo의 `feat/fluxcd-bootstrap` 브랜치) |
| **Kustomization** | Git 경로를 클러스터에 적용하는 단위 (`infrastructure`, `apps`) |
| **HelmRepository** | Helm chart 소스 등록 (e.g., Bitnami) |
| **HelmRelease** | Helm chart 배포 선언 (values 포함) |

### Reconciliation 흐름

```
Git Push
  │
  ▼
GitRepository (source-controller가 주기적 poll)
  │
  ▼
Kustomization/flux-system (k8s/clusters/homelab/ 적용)
  │
  ├──▶ Kustomization/infrastructure (k8s/infrastructure/ 적용)
  │       └── HelmRepository 등록 (Bitnami 등)
  │
  └──▶ Kustomization/apps (k8s/apps/ 적용, infrastructure 완료 후)
          └── HelmRelease 배포 (nginx 등)
```

`apps`는 `infrastructure`에 의존(`dependsOn`)하므로, Helm repo 등록이 먼저 완료된 후 앱이 배포됩니다.

## 디렉토리 구조

```
k8s/
├── clusters/
│   └── homelab/                    # 클러스터 엔트리포인트
│       ├── flux-system/            # Flux 자체 매니페스트 (자동 생성, 수정 금지)
│       │   ├── gotk-components.yaml  # Flux 컨트롤러 CRD/Deployment
│       │   ├── gotk-sync.yaml        # 자기 자신을 reconcile하는 설정
│       │   └── kustomization.yaml
│       ├── infrastructure.yaml     # → k8s/infrastructure/ 를 reconcile
│       └── apps.yaml               # → k8s/apps/ 를 reconcile (infrastructure 이후)
│
├── infrastructure/                 # 클러스터 인프라 (앱보다 먼저 적용)
│   ├── kustomization.yaml
│   └── sources/                    # Helm 리포지토리 등록
│       ├── kustomization.yaml
│       └── bitnami.yaml            # Bitnami Helm repo
│
└── apps/                           # 워크로드 배포
    ├── kustomization.yaml
    └── nginx/                      # 앱 단위 디렉토리
        ├── kustomization.yaml
        └── helmrelease.yaml        # HelmRelease CRD
```

### 각 레이어의 역할

| 레이어 | 경로 | 역할 | 예시 |
|---|---|---|---|
| **clusters** | `clusters/homelab/` | Flux 엔트리포인트, 클러스터별 설정 | flux-system, Kustomization 참조 |
| **infrastructure** | `infrastructure/` | 앱 배포 전 필요한 공통 인프라 | HelmRepository, cert-manager, ingress |
| **apps** | `apps/` | 실제 워크로드 | nginx, 모니터링, 사용자 앱 |

## Getting Started

### 사전 요구

- 클러스터에 FluxCD가 부트스트랩되어 있어야 합니다
- `GITHUB_TOKEN` 환경 변수 (repo 권한 필요)

### 초기 부트스트랩

```bash
# GitHub Token 설정
export GITHUB_TOKEN=ghp_xxxxx

# FluxCD 부트스트랩 (justfile 레시피)
just flux bootstrap <github-owner> <repo-name> <branch>

# 예시
just flux bootstrap vanillacake369 tonys-homelab main
```

### 상태 확인

```bash
# 전체 FluxCD 상태
just flux status

# 수동 reconcile 트리거
just flux reconcile

# 클러스터에서 직접 확인
ssh -F .cache/ssh-config k8s-master-1 "flux get all"
ssh -F .cache/ssh-config k8s-master-1 "flux get helmreleases -A"
```

## How to Use

### 새로운 앱 추가 (HelmRelease)

1. **Helm 소스가 없으면 등록:**

```yaml
# k8s/infrastructure/sources/my-repo.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: my-repo
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.example.com
```

`infrastructure/sources/kustomization.yaml`에 리소스 추가:
```yaml
resources:
  - bitnami.yaml
  - my-repo.yaml  # 추가
```

2. **앱 디렉토리 생성:**

```bash
mkdir -p k8s/apps/my-app
```

3. **HelmRelease 작성:**

```yaml
# k8s/apps/my-app/helmrelease.yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: my-app
  namespace: default
spec:
  interval: 30m
  chart:
    spec:
      chart: my-chart
      version: ">=1.0.0 <2.0.0"
      sourceRef:
        kind: HelmRepository
        name: my-repo
        namespace: flux-system
  values:
    replicaCount: 1
    # ... chart-specific values
```

4. **Kustomization 등록:**

```yaml
# k8s/apps/my-app/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
```

`apps/kustomization.yaml`에 추가:
```yaml
resources:
  - nginx
  - my-app  # 추가
```

5. **커밋 & 푸시 → FluxCD가 자동 배포**

### 별도 Git 리포지토리 추가

FluxCD는 여러 GitRepository를 모니터링할 수 있습니다:

```yaml
# k8s/infrastructure/sources/external-repo.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: external-apps
  namespace: flux-system
spec:
  interval: 5m
  url: https://github.com/owner/another-repo
  ref:
    branch: main
```

이후 Kustomization에서 해당 소스를 참조:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: external-apps
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: external-apps  # 위에서 등록한 이름
  path: ./k8s/apps
```

## Values 설정 가이드

### HelmRelease values

`spec.values`에 Helm chart values를 직접 선언합니다:

```yaml
spec:
  values:
    replicaCount: 2
    image:
      tag: "1.27"
    resources:
      requests:
        cpu: 10m
        memory: 32Mi
```

### chart 버전 고정 전략

| 패턴 | 의미 | 용도 |
|---|---|---|
| `version: "1.2.3"` | 정확한 버전 | 프로덕션, 안정성 우선 |
| `version: ">=1.0.0 <2.0.0"` | 범위 지정 | 마이너/패치 자동 업데이트 |
| `version: "*"` | 최신 | 테스트 환경 |

### Reconciliation 주기

| 리소스 | 필드 | 권장값 | 설명 |
|---|---|---|---|
| GitRepository | `spec.interval` | 1m | Git 변경 감지 주기 |
| Kustomization | `spec.interval` | 5-10m | 매니페스트 적용 주기 |
| HelmRepository | `spec.interval` | 1h | chart 인덱스 갱신 주기 |
| HelmRelease | `spec.interval` | 30m | Helm release 상태 확인 주기 |

## 주의사항

- `clusters/homelab/flux-system/` 내 파일은 **수동 수정 금지** — Flux가 자동 관리
- `prune: true` 설정으로 Git에서 삭제한 리소스는 클러스터에서도 자동 삭제됨
- HelmRelease 삭제 시 해당 Helm release도 클러스터에서 제거됨
- Flux 컨트롤러 자체는 `flux-system` 네임스페이스에서 실행됨

## Justfile 레시피

| 레시피 | 설명 |
|---|---|
| `just flux bootstrap <owner> [repo] [branch]` | FluxCD 초기 설치 (GITHUB_TOKEN 필요) |
| `just flux status` | 전체 Flux 리소스 상태 조회 |
| `just flux reconcile` | Git 소스 + Kustomization 수동 동기화 |
