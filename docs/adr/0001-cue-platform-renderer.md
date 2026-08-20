# ADR 0001: CUE 기반 플랫폼 렌더러

## 상태

채택. `tonys-gis` Harbor digest 검증 후 Flux production 연결까지 활성화했다.

## 조사 결과

| 항목 | 공통 필드 | 앱별 차이 | 플랫폼화 적합성 | 비고 |
| -- | ----- | ----- | -------- | -- |
| Namespace | 이름, Gateway route-access label, Pod Security labels | `bookorbit`는 baseline enforce, `tonys-gis`는 restricted 가능 | 높음 | WebService는 restricted 기본값으로 생성 |
| ServiceAccount | 이름/namespace, pull secret | `tonys-gis`는 Harbor pull secret, `bookorbit`는 public image라 SA 없음 | 중간 | 초기 WebService는 pull secret만 지원 |
| Deployment | labels, selector, probes, resources, securityContext, read-only root | `bookorbit`는 PVC/nodeSelector/Recreate, `tonys-gis`는 stateless Spring Boot | 높음 for stateless | 첫 대상은 `tonys-gis`만 |
| Service | ClusterIP, http port, selector | port 8080 vs 3000 | 높음 | 단일 Service만 지원 |
| HTTPRoute | `gateway/homelab` parentRef, backendRef | `bookorbit`는 catch-all, `tonys-gis`는 `/tonys-gis` prefix | 높음 | host는 intent에 두지만 현재 Gateway는 HTTP host match 미사용 |
| NetworkPolicy | default deny, ingress entity, DNS egress | `bookorbit`는 DB/setup Job 규칙 필요 | 높음 for stateless | WebService는 ingress+DNS만 생성 |
| Image | digest pin 선호, `latest` 금지 | `tonys-gis`는 Harbor digest pin 사용 | 높음 | schema는 digest 필수 |
| ConfigMap/Secret | Secret 값은 SOPS, 앱은 ref만 사용 | `bookorbit`는 ConfigMap/Secret/Job 필요 | 낮음 for first pass | `secretEnv` ref만 지원 |
| Flux path | `deploy/k8s/clusters/homelab` 루트, infrastructure dependsOn | `bookorbit`는 전용 KS, generated apps는 공용 KS | 중간 | 앱 수 증가 전까지 단일 generated KS 유지 |
| Generated 관례 | `flux-system`은 generated로 존재 | 플랫폼 generated 관례 없음 | 높음 | `deploy/k8s/generated/**` 신설 |

## 대안 비교

| 대안 | YAML 중복 제거 | 타입 안정성 | 교차 필드 검증 | GitOps 중립성 | 디버깅 난이도 | generated 관리 | 운영 비용 | rollback |
| -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Kustomize component 중심 | 중간 | 낮음 | 낮음 | 높음 | 낮음 | 낮음 | 낮음 | 쉬움 |
| CUE direct renderer | 높음 | 높음 | 높음 | 높음 | 중간 | 중간 | 중간 | 쉬움 |
| CUE + Timoni | 높음 | 높음 | 높음 | 중간-높음 | 중간-높음 | 중간 | 높음 | 중간 |

## 결정

CUE direct renderer를 채택한다.

근거:

- 현재 반복은 `Namespace`, `ServiceAccount`, `Deployment`, `Service`,
  `HTTPRoute`, `CiliumNetworkPolicy`의 stateless web service 패턴에 집중되어 있다.
- Kustomize component는 YAML 라인 수를 줄일 수 있지만 route host/path, digest,
  probe/resource 필수성 같은 교차 필드 검증에는 약하다.
- Timoni는 OCI module 배포와 semantic module versioning이 필요할 때 유리하지만,
  현재는 단일 repo 안에서 generated YAML을 Flux가 소비하면 충분하다.
- Flux와 Argo CD가 같은 generated Kubernetes 리소스를 소비할 수 있어 GitOps
  컨트롤러 중립성이 유지된다.

## 구조

```text
deploy/platform/
├── api/        # 앱 작성자가 쓰는 public contract
├── policies/   # 모든 앱에 강제할 불변 조건
├── profiles/   # 선택 가능한 기본값 묶음
├── render/     # Kubernetes object renderer
├── apps/       # SSoT app intent
└── tests/      # negative fixtures

deploy/k8s/generated/apps/
└── tonys-gis/
```

물리 디렉터리는 책임별로 나누되, CUE build는 `deploy/tools/platform-render.sh`가 임시
context로 합성한다. CUE는 디렉터리 단위 package resolution을 하므로, 이 repo의
초기 단계에서는 module import graph보다 deterministic 합성을 우선한다.

## Timoni 평가

| 판단 기준 | 현재 필요 여부 | 근거 |
| --- | --- | --- |
| 여러 repository에서 동일 module 소비 | 아니오 | 현재 platform consumer는 `tonys-homelab` 하나 |
| OCI module 배포 | 아니오 | Git committed generated YAML로 충분 |
| semantic module versioning | 아니오 | 앱 하나의 초기 renderer |
| Cosign signing/verification | 아니오 | 이미지 digest pin이 더 시급 |
| 여러 cluster에 immutable package 배포 | 아니오 | homelab 단일 cluster |
| 단일 repo 내 CUE rendering으로 충분한가 | 예 | Flux/Argo 모두 generated path 소비 가능 |

미래에 Timoni로 옮기려면 `deploy/platform/api`와 `deploy/platform/render`의 경계를 module
schema와 template 경계로 유지하면 된다. `deploy/platform/apps/*.cue`는 Timoni bundle
values로 이전 가능해야 한다.

## Flux adapter 판단

현재 `deploy/k8s/clusters/homelab/apps.yaml`은 `./deploy/k8s/apps`를 보지만 실제 resources는
비어 있다. `bookorbit`는 상태저장 앱이라 전용 Flux Kustomization을 가진다.

선택지는 두 가지다.

| 방식 | 장점 | 단점 | 현재 판단 |
| --- | --- | --- | --- |
| 하나의 `generated-apps` KS | 단순, 앱 수가 적을 때 관리 쉬움 | 한 앱 장애가 wait 상태에 영향 | 채택 후보 |
| 앱별 Flux KS | 격리와 헬스 추적이 좋음 | 앱마다 Flux YAML 반복 | 앱 수 증가 후 |

초기에는 하나의 `generated-apps` KS가 충분하다. 현재 `tonys-gis`는 Harbor
digest로 고정했고, `deploy/k8s/clusters/homelab/generated-apps.yaml`을 통해 production
Flux 루트에 연결되어 있다. 앱 수가 늘거나 개별 health/rollback 격리가 필요해질
때 앱별 Flux Kustomization을 재평가한다.

## Argo adapter 판단

Argo CD는 현재 운영 컨트롤러가 아니다. `deploy/gitops/argo`에는 AppProject와
ApplicationSet 초안만 둔다. Argo pilot을 적용하려면 먼저 Flux ownership을
suspend하거나 경로를 분리해야 한다.

## Semantic difference

`tonys-gis` 기존 manifest 대비 의도된 차이:

- image가 `:0.1.0` tag에서 Harbor `@sha256` digest contract로 바뀐다.
- `generated-apps` Flux Kustomization이 `deploy/k8s/generated/apps` 경로를 적용한다.
- YAML key order와 list formatting은 CUE export 기준으로 안정화된다.

의도하지 않은 차이는 `just manifest diff`와 기존 manifest 비교로 제거한다.

## Rollback

1. Flux adapter를 활성화했다면 `suspend: true`로 되돌린다.
2. 루트 Kustomization에 `generated-apps.yaml`을 추가했다면 해당 참조를 제거한다.
3. `deploy/k8s/generated/apps/tonys-gis`를 삭제하거나 이전 커밋으로 되돌린다.
4. 기존 `tonys-gis` repo의 `deploy/k8s/base` + Skaffold 직접 배포 경로로 복귀한다.

## BookOrbit gap

`bookorbit`는 `#WebService`만으로 바로 이전하지 않는다.

필요한 추가 contract:

- PVC와 node co-location
- StatefulSet/Postgres
- setup Job
- ConfigMap envFrom
- DB egress/ingress NetworkPolicy
- readOnlyRootFilesystem 예외
- Recreate rollout

이 반복이 두 번째 앱에서도 확인되기 전까지 `StatefulService` 같은 abstraction은 만들지 않는다.
