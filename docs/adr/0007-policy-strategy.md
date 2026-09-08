# ADR 0007: 정책과 Guardrail 전략

## 상태

채택.

## 맥락

현재 repo는 Kyverno policy, CUE policy, 로컬 check를 함께 사용한다. 정책 자체는 유용하지만,
파일 수와 rule 수가 늘면 사용자가 Kubernetes 기본 동작보다 정책 우회 방법을 먼저 배우게 된다.

현재 목표는 "앱을 안전하게 올리되, 정책이 학습을 가리지 않게 하는 것"이다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| 정책 없음 | Kubernetes 기본값만 사용 | 학습 단순 | 실수 방지 약함 |
| 문서/runbook only | 규칙은 문서화하고 사람이 확인 | 이해 쉬움 | 자동 enforcement 없음 |
| 로컬 lint/check | CI/just에서 검증 | 클러스터 admission 영향 없음 | 직접 apply 시 우회 가능 |
| Kyverno audit | admission은 허용, 위반 보고 | 학습 방해 적음 | 실수 차단 없음 |
| Kyverno enforce | admission 단계 차단 | 운영 안전성 높음 | 초기 학습/디버깅 비용 증가 |
| CUE schema policy | 생성 전 contract에서 차단 | generated 앱에 강함 | raw manifest에는 적용 안 됨 |

## 결정

정책은 3단계로 운영한다.

1. 로컬 `just check k8s`에서 구조적 오류를 먼저 잡는다.
2. Kyverno는 최소 보안 규칙만 enforce한다.
3. 새 정책은 audit 또는 로컬 check로 시작하고, 반복 위반과 수정 방법이 문서화된 뒤 enforce한다.

## 현재 최소 enforcement 대상

- privileged container 금지
- `latest` image 금지
- read-only root filesystem 요구
- automount service account token false 요구
- Gateway route namespace 제한

## 근거

- 단일 사용자 홈랩에서도 privileged container, latest image, service account token 자동 mount는 반복 실수 위험이 크다.
- 반대로 모든 PodSecurity/NetworkPolicy 세부 규칙을 초기에 강제하면 학습 속도가 떨어진다.
- 로컬 check는 Git에 들어가기 전 빠르게 실패하므로 admission error보다 수정 비용이 낮다.
- Kyverno는 Kubernetes admission controller로 정책을 적용하므로 GitOps 외부 apply도 차단할 수 있다.
- CUE policy는 generated 앱에만 적용하고, raw manifest 학습 경로를 가리지 않는다.

## 운영 명세

정책 추가 절차:

1. 위반 예시 manifest를 작성한다.
2. 로컬 check 또는 Kyverno test로 실패를 확인한다.
3. 해결 방법을 policy 주석 또는 runbook에 적는다.
4. audit으로 시작한다.
5. 실제 앱 2개 이상에서 수정 패턴이 확인되면 enforce로 전환한다.

정책 파일 수 관리:

- 같은 책임의 rule은 한 디렉토리에 둔다.
- 정책 이름은 금지/요구 동사를 포함한다.
- 예외는 정책 안에 숨기지 않고 앱 manifest 또는 ADR에 명시한다.

## 확장 전략

| 상황 | 선택 |
| --- | --- |
| 개인 앱 학습 | 최소 enforce |
| 외부 공개 앱 | Pod Security, NetworkPolicy, image provenance 강화 |
| 팀/다중 사용자 | namespace quota, RBAC, exception process 추가 |
| generated 앱 증가 | CUE schema policy 확대 |

## 재검토 조건

- 정책 때문에 원인 파악 시간이 배포 시간보다 길어진다.
- 예외가 3개 이상 누적된다.
- 외부 사용자에게 공개되는 앱이 생긴다.
- supply-chain 보안 요구가 생긴다.

## 근거 자료

- 로컬: `deploy/policy/k8s/kyverno`, `deploy/platform/policies`, `justfile`
- Kyverno introduction: https://kyverno.io/docs/introduction/
- Kubernetes Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Kubernetes admission controllers: https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/
