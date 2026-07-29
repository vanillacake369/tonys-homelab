# AI Serving Boundary

이 문서는 homelab Kubernetes 워크로드가 호스트 소유 AI 런타임을 소비할 때의 경계를 정의한다.
현재 클러스터에는 AI serving workload, model, proxy manifest 를 배포하지 않는다.

## Decision

- `homelab-1`의 GPU/NPU는 호스트가 소유한다.
- Kubernetes VM에는 GPU/NPU passthrough 를 하지 않는다.
- 실제 프로젝트가 AI inference 를 필요로 할 때, 프로젝트는 클러스터 내부에서 직접 GPU/NPU workload 를 띄우지 않고 호스트의 AI endpoint 를 네트워크로 소비한다.
- 현재 저장소에는 consumer/proxy 계약만 남기고, Ollama 같은 AI runtime 과 테스트 모델은 배포하지 않는다.

## Future Flow

1. 호스트에서 AI runtime 을 별도 Nix change 로 활성화한다.
2. runtime 은 우선 loopback 또는 전용 host-side proxy 에만 bind 한다.
3. 프로젝트별 proxy 는 인증, rate limit, request/response size limit, timeout 을 가진다.
4. Kubernetes 앱은 직접 host runtime 에 붙지 않고, 프로젝트 namespace 의 proxy service 를 호출한다.
5. NetworkPolicy 는 해당 앱에서 proxy 로 가는 egress 와 proxy 에서 host endpoint 로 가는 egress 만 허용한다.

## Proxy Contract

- Namespace: 프로젝트 namespace.
- Service name: 프로젝트가 정한다. 예: `ai-proxy`.
- Upstream: host-owned AI endpoint. 예: `http://192.168.45.82:11434`.
- External exposure: 기본 금지. Gateway/HTTPRoute 는 사용자 요청이 있을 때만 추가한다.
- Authentication: 프로젝트 단위 token 또는 mTLS 중 하나를 선택한다.
- Observability: request count, latency, upstream error, timeout, model name 을 수집한다.
- Failure mode: upstream unavailable 시 fast fail 하고 앱이 degrade path 를 갖도록 한다.

## Non-Goals

- 클러스터 안에 GPU/NPU device plugin 을 설치하지 않는다.
- Ollama, ROCm serving container, model download job 을 GitOps 앱으로 배포하지 않는다.
- 공용 cluster-wide AI endpoint 를 만들지 않는다.
- passthrough 기반 VM accelerator 설계를 기본 경로로 삼지 않는다.

## Validation Checklist

- 호스트 AI runtime 이 필요한 프로젝트 변경에서만 활성화되어 있다.
- `deploy/k8s/apps/kustomization.yaml`에 범용 AI workload 가 등록되어 있지 않다.
- proxy Service 는 프로젝트 namespace 내부에만 노출된다.
- CiliumNetworkPolicy 가 앱과 proxy 의 egress 를 명시적으로 제한한다.
- host endpoint 는 필요한 VM/K8s subnet 또는 Tailscale ACL 에만 열려 있다.
- 모델 저장 경로와 rollback 절차가 프로젝트 문서에 기록되어 있다.
