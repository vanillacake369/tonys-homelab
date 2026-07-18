# MagicDNS GitOps 앱 온보딩 런북

이 문서는 `bookorbit`과 `tonys-gis`처럼 Tailscale MagicDNS
`https://homelab-1.taild94cc1.ts.net` 아래로 노출되는 앱을 복구, 변경, 검증하는
운영자 온보딩 절차다.

## 현재 기준

| 항목 | 기준 |
| --- | --- |
| 운영 GitOps 컨트롤러 | Flux |
| 외부 진입점 | Tailscale Serve -> Cilium Gateway `10.0.20.240:80` |
| BookOrbit 경로 | `/api/v1/health` |
| Tonys GIS 경로 | `/tonys-gis/api/hello`, `/tonys-gis/actuator/health/readiness` |
| Tonys GIS SSoT | `deploy/platform/apps/tonys-gis.cue` |
| Tonys GIS 생성물 | `deploy/k8s/generated/apps/tonys-gis/` |
| 수동 수정 금지 | `deploy/k8s/generated/**`, `deploy/k8s/clusters/homelab/flux-system/**` |

`bookorbit`은 현재 상태저장 앱이므로 `deploy/k8s/apps/bookorbit/`의 명시적 manifest를
사용한다. `tonys-gis`는 CUE intent에서 deterministic하게 생성된 manifest를
Flux가 소비한다.

## 도구

| 목적 | 도구 | 비고 |
| --- | --- | --- |
| 로컬 검증 | `nix develop`, `just ci` | CI와 같은 진입점으로 맞춘다. |
| GitHub Actions 확인 | 비활성 | 이전 workflow는 `.github/workflows.disabled/`에 보존한다. |
| 클러스터 접근 | `just ssh k8s-master-1` 또는 `ssh -F .cache/ssh-config k8s-master-1` | 로컬 kubeconfig가 없어도 검증 가능하다. |
| Flux 수렴 | `just flux status`, `just flux reconcile` | 필요할 때만 강제 reconcile한다. |
| 외부 검증 | `curl` | HTTP status와 응답 body를 같이 본다. |

Docker CLI/daemon은 필수 경로가 아니다. Registry digest 조회는 `crane digest`를
우선 사용하고, `skopeo inspect docker://...`는 보조 옵션으로만 둔다.

## 배포 루프

1. 변경 전 현재 상태를 본다.

```bash
git status --short
just ci
```

2. `tonys-gis` intent를 바꿨다면 생성물도 갱신한다.

```bash
just render tonys-gis
just check-app tonys-gis
just check-generated
```

3. 커밋하고 푸시한다.

```bash
git add deploy/platform deploy/k8s/generated docs justfile
git commit -m "feat(platform): update tonys gis deployment"
git push
```

4. 로컬 CI가 통과하는지 확인한다.

```bash
just ci
```

실패하면 로그의 첫 번째 concrete error를 기준으로 수정한다. 같은 명령을 반복하기
전에 원인을 바꿔야 한다.

5. Flux가 최신 Git revision으로 수렴했는지 확인한다.

```bash
just flux status
CONFIRM_DEPLOY=homelab just cd gitops
ssh -F .cache/ssh-config k8s-master-1 "kubectl get kustomizations -A"
```

6. Kubernetes workload를 확인한다.

```bash
ssh -F .cache/ssh-config k8s-master-1 "kubectl -n bookorbit get pods,svc,httproute -o wide"
ssh -F .cache/ssh-config k8s-master-1 "kubectl -n tonys-gis get pods,deploy,svc,httproute -o wide"
ssh -F .cache/ssh-config k8s-master-1 "kubectl -n bookorbit rollout status deployment/bookorbit --timeout=120s"
ssh -F .cache/ssh-config k8s-master-1 "kubectl -n tonys-gis rollout status deployment/tonys-gis --timeout=120s"
```

7. MagicDNS endpoint를 확인한다.

```bash
curl -fsS https://homelab-1.taild94cc1.ts.net/api/v1/health
curl -fsS https://homelab-1.taild94cc1.ts.net/tonys-gis/api/hello
curl -fsS https://homelab-1.taild94cc1.ts.net/tonys-gis/actuator/health/readiness
```

성공 기준은 HTTP 200뿐 아니라 응답 body가 해당 앱의 응답인 것이다.
`/tonys-gis`가 BookOrbit HTML을 반환하면 `tonys-gis` HTTPRoute가 없거나 Gateway
match가 깨진 상태다.

## 장애 분기

| 증상 | 의미 | 처리 |
| --- | --- | --- |
| CI에서 `just: not found` | devShell과 CI entrypoint 불일치 | `flake.nix` devShell과 workflow가 같은 도구를 쓰게 한다. |
| CI Nix setup에서 disk full | runner 디스크 최적화 단계와 cache import 충돌 | 불필요한 disk surgery를 제거하고 `just check` 단일 경로를 유지한다. |
| Flux `Ready=False` | Git desired state와 클러스터 실제 상태가 불일치 | `flux get kustomization`, `kubectl describe`로 concrete object를 찾는다. |
| MagicDNS 502 | Tailscale Serve backend 또는 Gateway IP 접근 실패 | VM, Gateway address, `tailscale serve status`를 확인한다. |
| MagicDNS 503 | backend pod/service가 ready하지 않음 | rollout, endpoints, pod events를 확인한다. |
| image pull 실패 | digest, registry, pull secret, node DNS 문제 | digest와 `imagePullSecrets`를 먼저 확인한다. |

## 보안 규칙

- Secret 값은 repo와 generated manifest에 넣지 않는다.
- 로컬 git remote에 토큰이 포함된 URL을 남기지 않는다.
- 운영 이미지는 tag-only가 아니라 digest로 고정한다.
- `deploy/k8s/generated/**`는 생성 산출물이므로 직접 수정하지 않는다.
- Flux와 Argo CD가 같은 리소스를 동시에 reconcile하게 만들지 않는다.

## Rollback

가장 작은 rollback 단위는 마지막 Git 커밋 revert다.

```bash
git revert <bad-commit>
git push
CONFIRM_DEPLOY=homelab just cd gitops
```

`tonys-gis`만 급히 내릴 때는 `deploy/k8s/clusters/homelab/generated-apps.yaml` 연결을
되돌리거나 `deploy/k8s/generated/apps/kustomization.yaml`에서 해당 앱 디렉터리를 제거한
커밋을 만든다. BookOrbit 회귀 여부는 항상 함께 확인한다.

```bash
curl -fsS https://homelab-1.taild94cc1.ts.net/api/v1/health
```

## 다음 개선 후보

| 후보 | 판단 |
| --- | --- |
| `tonys-gis` 이미지 build/push/digest 갱신을 CI release job으로 자동화 | 현재 digest pin은 수동 갱신이므로 반복 배포 비용을 줄일 수 있다. |
| MagicDNS smoke test를 CI 이후 별도 운영 probe로 자동화 | public runner에서 Tailscale 접근이 안 되면 self-hosted runner나 내부 cron이 필요하다. |
| `bookorbit`를 CUE로 이전 | PVC, StatefulSet, setup Job 반복이 다른 앱에서도 확인될 때 진행한다. |
| Argo CD pilot | Flux ownership을 끄거나 경로를 분리할 때만 적용한다. |
| Timoni 도입 | 여러 repo/cluster에서 같은 module을 versioned OCI package로 소비할 때 재평가한다. |
