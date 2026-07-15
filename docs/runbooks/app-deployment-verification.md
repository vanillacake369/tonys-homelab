# App deployment verification runbook

이 문서는 `bookorbit`과 `tonys-gis`가 실제로 배포되어 외부에서 접근 가능한지
확인하는 절차다. 로컬 `kubectl` context가 비어 있을 수 있으므로 기본 경로는
`homelab-1`을 통한 `k8s-master-1` SSH 실행이다.

## 현재 관찰 요약

2026-07-16 점검 기준:

- `homelab-1`의 Tailscale Serve는
  `https://homelab-1.taild94cc1.ts.net/`를 `http://10.0.20.240:80`으로
  프록시한다.
- Kubernetes VM 세 대가 꺼져 있으면 Gateway IP `10.0.20.240`과 master
  `10.0.20.10`에 도달할 수 없어 외부 요청은 `502` 또는 `503`이 된다.
- VM 기동 후 `bookorbit`은 `1/1 Running`과 외부
  `/api/v1/health` `HTTP 200`까지 확인됐다.
- `bookorbit` Flux Kustomization은 `Ready=True`여야 한다. 과거에는 실패한
  `bookorbit-setup` Job의 immutable `spec.template` 충돌로 `Ready=False`가 된 적이
  있으므로 같은 메시지가 재발하면 아래 분기표를 따른다.
- `tonys-gis`는 `platform/apps/tonys-gis.cue`를 SSoT로 하고,
  `k8s/generated/apps/tonys-gis` 생성물을 `generated-apps` Flux Kustomization이
  production에 적용한다.
- `tonys-gis` 이미지는
  `harbor.home.arpa/tonys-gis/tonys-gis@sha256:cbae25cb11b4729d4e15f9f2885fbcac0bf787e1df791e5b8c541be4e6e3194c`
  로 고정되어 있다.
- Docker CLI/daemon이 없는 환경은 지원 대상이다. 다만 로컬 이미지 build는
  Podman machine이 정상 기동되어야 하며, macOS에서 Buildah 단독 실행은 rootless
  mount/image store 제약 때문에 표준 경로로 보지 않는다.

## 필요한 도구

| 목적 | 기본 도구 | 대안 | 비고 |
| --- | --- | --- | --- |
| SSH 경유 운영 점검 | `just`, `ssh`, `tailscale`, `jq`, `nix` | 직접 SSH config | `justfile`이 topology와 Tailscale peer를 합쳐 `.cache/ssh-config`를 만든다. |
| 클러스터 상태 확인 | 원격 `kubectl`, 원격 `flux` | 로컬 kubeconfig | 로컬 context가 비어 있으면 원격 실행을 표준으로 둔다. |
| manifest 검증 | `kustomize`, `kubeconform`, `kyverno`, `yq` | `kubectl apply --dry-run=server` | server-side dry-run은 클러스터 접근이 필요하다. |
| `tonys-gis` 렌더링 | `cue`, `just render`, `just check-app` | 없음 | generated output은 직접 수정하지 않는다. |
| 이미지 build/push | `podman` | `buildah` | Docker Desktop 제거 환경을 기본으로 둔다. |
| registry digest 조회 | `crane digest` | `skopeo inspect docker://...`, `regctl image digest` | `skopeo`의 `docker://`는 Docker daemon이 아니라 registry transport다. |
| 외부 접근 확인 | `curl` | 브라우저 | Tailscale MagicDNS 경로를 확인한다. |

## 로컬 container runtime 확인

Docker 패키지를 제거한 상태에서 `skopeo inspect docker://...`를 사용하는 것은
문제가 아니다. 여기서 `docker://`는 Docker daemon이 아니라 OCI/Docker registry
transport 이름이다.

이미지 build/push의 기준 경로는 Podman이다.

```bash
podman machine list
podman system connection list
podman machine start tonys-gis-dev
podman info
```

`podman machine start`가 장시간 반환되지 않거나 `podman info`가 socket refused를
반환하면 앱 빌드 문제가 아니라 로컬 Podman VM 문제다. 이 경우 다음 중 하나를
선택한다.

| 옵션 | 적용 상황 | 장점 | 리스크 |
| --- | --- | --- | --- |
| 기존 Podman machine 복구 | local build/push를 유지할 때 | 기존 `just image-build` 경로 유지 | machine/socket 상태 문제를 먼저 해결해야 한다. |
| 새 Podman machine 재생성 | 기존 machine이 꼬였을 때 | 상태를 단순화 | 로컬 image cache가 사라질 수 있다. |
| 원격 Linux builder 사용 | macOS Podman 문제가 반복될 때 | Kubernetes node와 가까운 Linux build 환경 | builder 권한과 registry credential 관리가 필요하다. |
| CI build로 위임 | 반복 가능한 release path가 필요할 때 | 개발자 로컬 runtime 의존 감소 | CI secret/registry/project bootstrap이 선행되어야 한다. |

macOS에서 `buildah` 단독 실행은 rootless mount 제약으로
`cannot mount using driver in rootless mode`가 발생할 수 있다. `buildah unshare`
형태로 일부 명령은 통과해도 image store 검증이 안정적이지 않으면 production build
경로로 채택하지 않는다.

## 계층별 확인 절차

### 1. Tailscale 및 VM 계층

```bash
tailscale status
just vm status
just vm start k8s-master-1 k8s-worker-1 k8s-worker-2
```

VM이 켜진 뒤 master SSH와 node readiness를 확인한다.

```bash
ssh -F .cache/ssh-config k8s-master-1 \
  'kubectl get nodes -o wide'
```

`homelab-1`에서 Gateway IP로 접근 가능한지도 확인한다.

```bash
ssh -F .cache/ssh-config homelab-1 \
  'tailscale serve status; nc -zvw2 10.0.20.240 80'
```

### 2. Gateway 계층

```bash
ssh -F .cache/ssh-config k8s-master-1 \
  'kubectl get gateway -n gateway homelab -o wide'

ssh -F .cache/ssh-config k8s-master-1 \
  'kubectl describe gateway -n gateway homelab | sed -n "1,140p"'
```

성공 기준:

- `ADDRESS`가 `10.0.20.240`
- `PROGRAMMED=True`
- listener condition `Accepted=True`, `ResolvedRefs=True`

### 3. BookOrbit 확인

```bash
just flux status

ssh -F .cache/ssh-config k8s-master-1 \
  'flux get kustomization bookorbit -n flux-system'

ssh -F .cache/ssh-config k8s-master-1 \
  'kubectl -n bookorbit get pods,svc,httproute,pvc -o wide'

ssh -F .cache/ssh-config k8s-master-1 \
  'kubectl -n bookorbit rollout status deployment/bookorbit --timeout=120s'

curl -k -sS -m 15 -w "\nHTTP %{http_code}\n" \
  https://homelab-1.taild94cc1.ts.net/api/v1/health
```

성공 기준:

- app pod와 postgres pod가 `Running`
- deployment가 `1/1`
- external health가 `HTTP 200`
- Flux Kustomization이 `Ready=True`

`bookorbit` 서비스는 정상인데 Flux만 `Ready=False`이고 메시지가
`Job/bookorbit/bookorbit-setup ... spec.template ... field is immutable`이면
기존 failed Job과 Git desired state가 충돌한 것이다.

처리 옵션:

| 옵션 | 적용 상황 | 장점 | 리스크 |
| --- | --- | --- | --- |
| 실패한 `bookorbit-setup` Job 삭제 후 Flux reconcile | setup Job 재실행이 안전하고 secret 값 기준 재부트스트랩을 허용할 때 | 가장 빠르게 Flux health 회복 | bootstrap script가 사용자 password reset 등 의도된 side effect를 다시 수행할 수 있다. |
| `bookorbit` Flux Kustomization에 `force: true` 검토 | Job immutable drift가 반복될 때 | GitOps가 immutable resource 교체를 처리 | Kustomization 전체에 replacement 성격이 생기므로 범위를 신중히 봐야 한다. |
| setup Job을 별도 one-shot 운영 절차로 분리 | 초기 bootstrap 이후 Job을 계속 reconcile할 필요가 없을 때 | steady-state GitOps 잡음 제거 | bootstrap 재현성이 문서/수동 절차로 이동한다. |
| Job 이름에 revision suffix 또는 generateName 패턴 검토 | setup script 변경을 새 Job으로 실행해야 할 때 | immutable 충돌 회피 | 완료 Job 누적과 prune 정책을 설계해야 한다. |

기본 권장 순서:

1. 현재 서비스 health가 `HTTP 200`인지 먼저 확인한다.
2. setup Job의 side effect가 허용되는지 확인한다.
3. 허용되면 failed Job 삭제 후 `flux reconcile kustomization bookorbit --with-source`.
4. 반복되면 `force: true`보다 먼저 setup Job의 ownership을 별도화할지 ADR로 판단한다.

### 4. Tonys GIS 확인

먼저 현재 상태를 본다.

```bash
ssh -F .cache/ssh-config k8s-master-1 \
  'kubectl get ns tonys-gis; kubectl -n tonys-gis get pods,deploy,svc,httproute,sa,secret -o wide'
```

namespace가 없거나 `generated-apps` Flux Kustomization이 없으면 production 연결이
깨진 상태다. intent 또는 renderer를 바꿨다면 다음 순서를 지킨다.

```bash
just check-app tonys-gis
just check-generated
```

운영 전환 필수 조건:

- Harbor가 배포되어 있고 `harbor.home.arpa`가 cluster node와 developer machine에서
  해석된다.
- Harbor project `tonys-gis`와 robot account가 존재한다.
- `tonys-gis` namespace에 `harbor-tonys-gis-pull` image pull secret이 존재한다.
- `platform/apps/tonys-gis.cue`의 digest가 실제 pushed image digest다.
- `k8s/clusters/homelab/generated-apps.yaml`이 production Kustomization으로
  연결되고 `suspend: false`다.

이미지 digest 조회 예시:

```bash
crane digest harbor.home.arpa/tonys-gis/tonys-gis:<tag>
skopeo inspect docker://harbor.home.arpa/tonys-gis/tonys-gis:<tag> \
  | jq -r .Digest
```

`skopeo inspect docker://...`의 `docker://`는 Docker daemon 의존성이 아니라
container registry transport 이름이다. Docker CLI/daemon을 제거한 환경에서도
registry 접근 권한과 DNS/CA가 맞으면 동작한다.

외부 확인:

```bash
curl -k -sS -m 15 -w "\nHTTP %{http_code}\n" \
  https://homelab-1.taild94cc1.ts.net/tonys-gis/api/hello

curl -k -sS -m 15 -w "\nHTTP %{http_code}\n" \
  https://homelab-1.taild94cc1.ts.net/tonys-gis/actuator/health/readiness
```

주의: `tonys-gis` HTTPRoute가 없으면 BookOrbit의 catch-all route가
`/tonys-gis/...` 요청까지 받아 HTML을 반환할 수 있다. 따라서 `HTTP 200`만 보지
말고 응답 body가 `tonys-gis` API 응답인지 확인해야 한다.

## 빠른 장애 분기표

| 증상 | 1차 확인 | 의미 | 다음 조치 |
| --- | --- | --- | --- |
| 외부 URL `502` | `just vm status`, `tailscale serve status` | Tailscale Serve backend 또는 VM/Gateway 불가 | VM 기동, Gateway IP 접근 확인 |
| 외부 URL `503` | `kubectl get gateway`, `kubectl get httproute`, pod readiness | Gateway는 있으나 backend가 ready하지 않음 | app pod/event/log 확인 |
| `/tonys-gis`가 BookOrbit HTML 반환 | `kubectl -n tonys-gis get httproute` | `tonys-gis` route 없음, BookOrbit catch-all 매칭 | `tonys-gis` 배포/route 생성 |
| `Flux Ready=False`와 Job immutable 오류 | `flux get kustomization bookorbit` | 기존 Job과 desired template 충돌 | failed Job 처리 옵션 검토 |
| image pull 실패 | `kubectl describe pod`, pull secret 확인 | digest/secret/registry/DNS 문제 | Harbor와 secret, digest 검증 |
| `harbor.home.arpa` 해석 실패 | node와 developer machine에서 `getent hosts`/`dig`/`curl` | registry bootstrap 미완료 또는 DNS 미구성 | Harbor infra 적용과 DNS/CA 정리 |
