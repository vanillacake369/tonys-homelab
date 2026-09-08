# ADR 0006: 앱 배포 Contract

## 상태

채택. 단, 신규 앱은 당분간 raw manifest를 우선한다.

## 맥락

현재 repo에는 두 경로가 공존한다.

- `deploy/k8s/apps/bookorbit`: 직접 작성한 Kubernetes manifest
- `deploy/platform/apps/*.cue` -> `deploy/k8s/generated/apps`: CUE 기반 generated manifest

사용자 온보딩 목표는 Kubernetes 기본기를 회복하고, AI가 만든 추상화를 직접 통제 가능한 수준으로
낮추는 것이다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| raw YAML | Kubernetes object를 직접 작성 | 학습/디버깅 최고 | 반복 증가 |
| Kustomize base/overlay | YAML을 얇게 조합 | kubectl/Flux와 자연스럽게 통합 | 교차 필드 검증 약함 |
| Helm chart | chart values로 앱 배포 | 외부 앱 설치 편함 | 직접 만든 앱에는 chart 유지 비용 |
| CUE renderer | intent를 schema로 검증 후 YAML 생성 | 반복 제거, policy 강제 | 추상화가 Kubernetes 학습 표면을 가림 |
| Timoni/OCI package | CUE module을 패키징 | 다중 repo/cluster 배포에 강함 | 현재 규모 대비 복잡 |

## 결정

신규 앱은 `deploy/k8s/apps/<app>` 아래 raw manifest 또는 얇은 Kustomize로 시작한다.

CUE renderer는 삭제하지 않는다. 단, 다음 조건 전까지 확장하지 않는다.

- 동일한 stateless web app 패턴이 3개 이상 반복된다.
- 사용자가 generated YAML의 semantic diff를 직접 설명할 수 있다.
- CUE contract 변경에 대한 negative fixture가 먼저 작성된다.

## 근거

- 현재 문제는 YAML 중복보다 통제감 부족이다.
- raw manifest는 Deployment, Service, HTTPRoute, PVC, Secret, NetworkPolicy의 실제 API를 드러낸다.
- Flux는 raw manifest와 generated manifest를 모두 적용할 수 있으므로 운영 경로는 유지된다.
- CUE는 교차 필드 검증에 유리하지만, 학습 단계에서는 추상화 비용이 더 크다.
- 상태저장 앱은 `#WebService` contract로 모델링하지 않는다.

## 운영 명세

신규 앱 최소 단위:

```text
deploy/k8s/apps/<app>/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
├── httproute.yaml
├── networkpolicy.yaml
└── kustomization.yaml
```

규칙:

- 앱별 namespace를 사용한다.
- image는 tag만 쓰지 않고 digest pin을 목표로 한다.
- readiness/liveness/startup probe를 명시한다.
- resources requests/limits를 명시한다.
- HTTPRoute는 shared Gateway(`gateway/homelab`)에 붙인다.
- NetworkPolicy는 default deny에서 필요한 ingress/egress만 연다.

## 확장 전략

| 앱 수/패턴 | 선택 |
| --- | --- |
| 1-2개 | raw manifest |
| 3개 이상 stateless 반복 | Kustomize component 또는 CUE 재평가 |
| 외부 Helm 앱 | HelmRelease 사용 |
| 여러 cluster/repo 배포 | Timoni 또는 chart packaging 검토 |

## 재검토 조건

- 같은 YAML 블록이 3회 이상 반복된다.
- 앱 추가 속도가 raw manifest 유지 속도를 넘는다.
- 보안/리소스/route 규칙을 사람이 반복 적용하면서 누락이 발생한다.

## 근거 자료

- 로컬: `deploy/platform/README.md`, `docs/adr/0001-cue-platform-renderer.md`, `deploy/k8s/apps/bookorbit`
- Kubernetes objects: https://kubernetes.io/docs/concepts/overview/working-with-objects/
- Kustomize: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- Flux concepts: https://fluxcd.io/flux/concepts/
