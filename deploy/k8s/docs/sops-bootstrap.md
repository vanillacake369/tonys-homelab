# Flux SOPS Bootstrap

이 문서는 Flux가 SOPS로 암호화된 Kubernetes Secret을 복호화하기 위해
필요한 `flux-system/sops-age` Secret의 관리 계약을 정의한다.

## 관리 모델

`sops-age`는 GitOps가 스스로 만들 수 없는 bootstrap root secret이다.
Flux가 Git의 `*.enc.yaml` 파일을 복호화하려면 먼저 클러스터 안에 age
private key가 있어야 하므로, 같은 Flux/SOPS 경로로 이 private key를
생성하려고 하면 순환 의존성이 생긴다.

따라서 이 저장소는 다음 경계를 사용한다.

| 항목 | 위치 | Git 추적 |
|---|---|---|
| cluster age public recipient | `.sops.yaml` | 예 |
| SOPS 암호화 Kubernetes Secret | `deploy/k8s/**/*.enc.yaml` | 예 |
| cluster age private key | password manager, operator machine | 아니오 |
| Flux 복호화 Secret | `flux-system/sops-age` | 클러스터 상태, Git 미추적 |

## Private Key 보관

BookOrbit cluster age private key는 기본적으로 다음 로컬 경로에 둔다.

```bash
$HOME/.config/sops/age/bookorbit-cluster.agekey
```

다른 위치를 사용할 때는 `SOPS_AGE_KEY_FILE`을 지정한다.

```bash
export SOPS_AGE_KEY_FILE=/path/to/bookorbit-cluster.agekey
```

private key 원본은 password manager나 오프라인 백업에 보관한다. 이 파일,
`kubectl get secret sops-age -o yaml` 출력, base64로 인코딩된 private key는
Git에 커밋하지 않는다.

## Bootstrap

Flux bootstrap 이후, SOPS로 암호화된 앱 Kustomization이 수렴하기 전에
`sops-age` Secret을 주입한다.

```bash
just k8s bootstrap-sops-age
```

이 명령은 다음을 수행한다.

1. 로컬 private key에서 public recipient를 계산한다.
2. 계산된 recipient가 `.sops.yaml`의 `&cluster` 값과 일치하는지 확인한다.
3. SSH로 Kubernetes master에 접속해 `flux-system/sops-age` Secret을
   idempotent하게 apply한다.
4. 클러스터에 들어간 Secret이 `.sops.yaml`의 cluster recipient와 일치하는지
   다시 확인한다.

## Verification

이미 Secret이 주입되어 있는지 확인하려면 다음 명령을 사용한다.

```bash
just k8s verify-sops-age
```

검증은 private key 값을 출력하지 않는다. 다만 검증 과정에서 클러스터 Secret의
private key를 읽을 수 있는 권한이 필요하므로, cluster-admin 수준 접근 권한이
있는 운영자만 실행한다.

## Recovery 순서

새 클러스터를 만들거나 disaster recovery를 수행할 때는 이 순서를 따른다.

1. Kubernetes control plane을 복구한다.
2. Flux를 bootstrap한다.
3. password manager에서 BookOrbit cluster age private key를 복원한다.
4. `SOPS_AGE_KEY_FILE`을 지정하거나 기본 경로에 key를 둔다.
5. `just k8s bootstrap-sops-age`를 실행한다.
6. `CONFIRM_DEPLOY=homelab just gitops reconcile` 또는 Flux reconcile로 Git 상태를
   다시 수렴시킨다.

## Key Rotation

cluster age key를 회전할 때는 새 private key를 먼저 안전한 secret store에
저장하고, 새 public recipient를 `.sops.yaml`의 `&cluster`에 반영한다. 그 다음
기존 `deploy/k8s/**/*.enc.yaml` 파일을 새 recipient로 rekey하고, 새 private
key로 `just k8s bootstrap-sops-age`를 실행한다.

회전 중에는 기존 키와 새 키 양쪽으로 복호화 가능한 전환 기간을 짧게 두고,
Flux 수렴이 확인된 뒤 이전 private key를 폐기한다.
