# Platform CUE renderer

이 계층의 SSoT는 `deploy/platform/apps/*.cue`다. `deploy/k8s/generated/**`는 생성 산출물이며
직접 수정하지 않는다.

## 현재 contract

초기 abstraction은 `#WebService` 하나만 제공한다.

지원 필드:

- `name`, `namespace`, `profile`
- `image.repository`, `image.digest`, `image.pullSecrets`
- `containerPort`
- `route.enabled`, `route.host`, `route.pathPrefix`
- `health.readinessPath`, `health.livenessPath`
- `resources.requests`, `resources.limits`
- `env`, `secretEnv`

의도적으로 지원하지 않는 것:

- sidecar, initContainer, arbitrary PodSpec
- HPA, PDB, StatefulSet, CronJob
- arbitrary Deployment patch
- arbitrary Kubernetes object forwarding

## 명령

```bash
just gitops plan
```

GitOps plan은 CUE 기반 generated manifest를 갱신하고 diff를 출력한 뒤 로컬 guardrail을
실행한다. CUE는 얕은 app values/schema/render 경계까지만 담당하고, admission policy는
현재 active path에서 제외한다. Renderer 자체를 디버깅할 때는 justfile의 private manifest
helper를 사용한다.

## 운영 주의

`deploy/platform/apps/tonys-gis.cue`의 digest는 현재 placeholder다. 실제 Flux 전환 전
Harbor에 push된 이미지의 digest로 교체해야 한다.
