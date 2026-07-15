# Flux generated-apps adapter

`apps-generated.yaml`은 `platform/apps/*.cue`에서 렌더링된
`k8s/generated/apps` 경로를 Flux가 소비하기 위한 adapter 초안이다.

현재 파일은 의도적으로 `suspend: true`이며
`k8s/clusters/homelab/kustomization.yaml`에서 참조하지 않는다. 이유는
`platform/apps/tonys-gis.cue`의 image digest가 아직 실제 Harbor digest로
검증되지 않았기 때문이다.

운영 전환 순서:

1. `platform/apps/tonys-gis.cue`의 digest를 실제 Harbor digest로 교체한다.
2. `just check-app tonys-gis`와 `just check-generated`를 통과시킨다.
3. `gitops/flux/apps-generated.yaml`을 `k8s/clusters/homelab/` 아래로 이동하거나
   동일 내용을 `generated-apps.yaml`로 추가한다.
4. 루트 `k8s/clusters/homelab/kustomization.yaml`에 참조를 추가한다.
5. `suspend: false`로 전환한다.
