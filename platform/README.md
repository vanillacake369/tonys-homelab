# Platform CUE renderer

이 계층의 SSoT는 `platform/apps/*.cue`다. `k8s/generated/**`는 생성 산출물이며
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
just render tonys-gis
just render-all
just check-app tonys-gis
just check-all
just check-generated
just diff-generated
just clean-generated
```

`check-app`은 CUE concrete export, negative fixture, Kustomize build,
kubeconform, deterministic re-render를 확인한다.

## 운영 주의

`platform/apps/tonys-gis.cue`의 digest는 현재 placeholder다. 실제 Flux 전환 전
Harbor에 push된 이미지의 digest로 교체해야 한다.
