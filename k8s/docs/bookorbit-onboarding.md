# BookOrbit 셀프호스팅 개발자 온보딩 가이드

이 문서는 **BookOrbit** 셀프호스팅 구성을 관리하고 개발하는 엔지니어를 위한 온보딩 가이드입니다. 
아키텍처 설계와 더불어, SOPS 시크릿 관리, AI 가드레일, 그리고 API 호출을 포함한 검증 방법을 구체적으로 기술합니다.

---

## 1. 아키텍처 및 현재 구성

클러스터는 **kubeadm 기반의 K8s (v1.35.x)**로 구성되어 있으며, **Cilium CNI (kube-proxy-less)** 및 **FluxCD (v2.8.x)** 기반의 GitOps 수렴 제어를 따릅니다.

### 3-Layer GitOps 토폴로지
전체 구성은 명확한 역할 분담을 위해 3계층(Layer)으로 격리되어 있습니다:
1. **Clusters (`clusters/homelab`)**: GitOps 동기화의 엔트리포인트이며 Flux 자체의 구성과 각 Kustomization 정의를 가집니다.
2. **Infrastructure (`infrastructure/`)**: 워크로드 구동에 선행하는 필수 공통 인프라 레이어입니다 (e.g., `local-path-provisioner` 스토리지 레이어, Cilium Gateway 등).
3. **Apps (`apps/`)**: 실제 동작하는 사용자 서비스 워크로드 레이어입니다 (e.g., `nginx`, `bookorbit`).

### BookOrbit 워크로드 설계 요약
- **BookOrbit App** (`apps/bookorbit/deployment.yaml`): 무상태(Stateless) Deployment로 구동되며, 롤아웃 시 볼륨 경합을 방지하기 위해 `strategy: Recreate` (replicas: 1) 설정을 가집니다.
- **PostgreSQL + pgvector** (`apps/bookorbit/postgres-statefulset.yaml`): DB 벡터 인덱스 생성을 위해 `pgvector`가 내장된 PostgreSQL 16 버전 StatefulSet으로 구동됩니다.
- **스토리지 및 Co-location**: 디스크 I/O 성능 및 단일 노드 스케줄링 제약 조건을 해결하기 위해 `local-path-provisioner` RWO 볼륨을 사용합니다. 이에 따라 App과 DB, 그리고 PVC 3개가 반드시 동일한 노드(`k8s-worker-1`)에 밀착되도록 `nodeSelector`를 명시적으로 고정했습니다.
- **네트워크 격리 (CiliumNetworkPolicy)**: `bookorbit` 네임스페이스는 기본적으로 모든 Ingress/Egress 트래픽을 차단(default-deny)합니다.
  - 앱 컨테이너는 오직 DB로의 egress (`:5432`)와 CoreDNS resolution (`:53`)만 허용됩니다.
  - DB 컨테이너는 오직 앱 컨테이너로부터의 ingress만 허용됩니다.
  - 외부 통신은 Cilium Gateway(Envoy 프록시)를 통해 외부에서 들어오는 트래픽(Ingress)과, admin setup을 수행하는 Job으로만 제한적으로 연결이 열려 있습니다.

---

## 2. 원칙과 규칙 (AI 가드레일 및 하네스)

모든 작업자(사람 및 AI 에이전트)는 아래의 가드레일 원칙을 반드시 엄수해야 합니다. 자세한 내용은 [gitops-guardrails.md](file:///Users/limjihoon/dev/tonys-homelab/k8s/docs/gitops-guardrails.md)를 참고하세요.

1. **평문 시크릿 커밋 절대 금지**: 모든 비밀정보(DB 암호, JWT 키, API 토큰 등)는 반드시 SOPS+age로 암호화되어 `secret.enc.yaml` 형태로 존재해야 합니다.
2. **`flux-system/` 디렉토리 직접 수정 금지**: `flux-system` 폴더 내부는 Flux가 자동 관리하므로 손대지 않으며, 신규 동기화 정의가 필요할 시 `clusters/homelab/` 직하에 별도 YAML을 정의합니다.
3. **자동 커밋/푸시 금지**: 작업의 전파(Git Push) 및 커밋은 반드시 사용자의 확인과 승인을 거친 뒤 수동으로 수행합니다.
4. **이미지/차트 버전 완전 고정 (Digest Pinning)**: `latest` 태그는 절대 사용 금지하며, 이미지 주소는 해시 digest(`@sha256:...`)를 포함해 핀(Pin)해야 합니다.
5. **보안 지향**: TLS 및 OIDC 인증 배선이 완료되지 않은 상태에서 무방비하게 외부 인터넷망에 public 노출을 시도하지 않습니다. (현재는 internal-only로 Tailscale을 통해 접근을 제한하고 있습니다.)
6. **동작성 정합 및 리소스 한계 제한**: 모든 워크로드에는 `resources.requests`와 `limits`가 선언되어 소규모 클러스터(Worker 노드 8GB) 내 OOMKill 및 스케줄링 실패를 방지하고, Liveness/Readiness probe가 명확히 주입되어야 합니다.

---

## 3. SOPS 시크릿 운용 방법

비밀번호 변경이나 키 회전이 필요할 시 다음 절차를 따릅니다.

### 로컬 환경 변수 설정
복호화에 필요한 cluster 전용 age 개인키가 로컬 PC에 존재해야 합니다.
```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/bookorbit-cluster.agekey"
```

### 시크릿 값 인플레이스(In-place) 수정
`sops` CLI를 사용하면 평문이 로컬 파일 시스템에 저장되지 않는 안전한 환경에서 값을 수정할 수 있습니다.
```bash
# 에디터를 띄워 편집 (저장 시 자동 암호화됨)
sops ./k8s/apps/bookorbit/secret.enc.yaml

# 비대화식으로 한 개 값만 바로 갱신
sops --set '["stringData"]["ADMIN_PASSWORD"] "NEW_STRONG_ADMIN_PASSWORD"' ./k8s/apps/bookorbit/secret.enc.yaml
sops --set '["stringData"]["USER_ALINA_PASSWORD"] "NEW_STRONG_USER_PASSWORD"' ./k8s/apps/bookorbit/secret.enc.yaml
```

### 수정 내역 검증 및 적용
```bash
# 복호화 검증 (정상 복호화되면 decrypt OK 출력)
sops --decrypt ./k8s/apps/bookorbit/secret.enc.yaml > /dev/null && echo 'decrypt OK'

# Git 커밋 및 푸시 (사용자 승인 후)
git add k8s/apps/bookorbit/secret.enc.yaml
git commit -m "chore(bookorbit): rotate admin and alina passwords"
git push

# FluxCD 강제 동기화 트리거
just flux-reconcile
# (또는 특정 kustomization만 강제 동기화)
ssh -F .cache/ssh-config k8s-master-1 "flux reconcile kustomization bookorbit -n flux-system --with-source"

# 변경된 Secret 값을 팟에 로드하기 위해 롤아웃 재기동 (필수)
ssh -F .cache/ssh-config k8s-master-1 "kubectl rollout restart deployment/bookorbit -n bookorbit"
```

---

## 4. 적용 및 확인 (검증 가이드)

### 클러스터 상태 확인 (`just` 명령어 사용)
클러스터에 배포된 리소스들의 상태를 조회하려면 아래 `just` 레시피들을 사용합니다.
```bash
# 전체 FluxCD 동기화 상태 요약 조회
just flux-status

# 마스터 노드에 ssh 접속하여 kubectl 직접 조회
ssh -F .cache/ssh-config k8s-master-1 "kubectl get pods -n bookorbit"
```

### API 검증 및 curl 호출 시나리오 (API Calling 지원)
현재 구성에서는 Tailscale 네트워크가 구성되어 있어 로컬 PC에서 호스트명(`https://homelab-1.taild94cc1.ts.net`)을 이용해 직접 API를 테스트할 수 있습니다.

#### 1) 헬스체크 API 호출
```bash
curl -s https://homelab-1.taild94cc1.ts.net/api/v1/health
# 기대 출력: {"status":"ok","info":{"database":{"status":"up"}},...}
```

#### 2) 어드민(admin) 계정 로그인 및 토큰 획득
`secret.enc.yaml`에 정의한 `ADMIN_USERNAME`과 `ADMIN_PASSWORD`로 REST API 로그인을 시도해 정상 접속 여부를 확인합니다.
```bash
# 로그인 요청 및 Access Token 추출
ADMIN_TOKEN=$(curl -s -X POST "https://homelab-1.taild94cc1.ts.net/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"9bf184ea59b35dfcd00a48b505a68bd2c65f02eab7a87aec"}' \
  | jq -r '.accessToken')

echo "Admin JWT Token: $ADMIN_TOKEN"
```

#### 3) 일반 유저(alina) 계정 로그인 및 토큰 획득
`setup-job`에 의해 자동으로 부트스트랩된 일반 사용자 `alina` 계정으로 REST API 로그인을 테스트합니다.
```bash
# alina 로그인 요청 및 Access Token 추출
USER_TOKEN=$(curl -s -X POST "https://homelab-1.taild94cc1.ts.net/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"alina","password":"5ef26086e70fee8ef0dc1790624b99cf8f058024de0f5cab"}' \
  | jq -r '.accessToken')

echo "User Alina JWT Token: $USER_TOKEN"
```

#### 4) 인증된 API 호출 (유저 프로필 조회)
발급된 `alina` 유저의 JWT 토큰을 Authorization 헤더에 실어 인증이 필요한 API를 호출할 수 있는지 검증합니다.
```bash
# 내 프로필 정보 조회
curl -s "https://homelab-1.taild94cc1.ts.net/api/v1/auth/me" \
  -H "Authorization: Bearer $USER_TOKEN" \
  | jq .
```

#### 5) 유저 목록 조회 (Admin 권한 필요 API)
일반 유저는 접근할 수 없고 오직 Admin만 수행할 수 있는 권한 검증 API가 정상적으로 인가/비인가 처리되는지 확인합니다.
```bash
# (A) 일반 유저 alina로 조회 시도 -> 403 Forbidden 기대
curl -s -w "\nHTTP Status: %{http_code}\n" \
  "https://homelab-1.taild94cc1.ts.net/api/v1/users" \
  -H "Authorization: Bearer $USER_TOKEN"

# (B) 어드민 admin으로 조회 시도 -> 200 OK 및 전체 사용자 목록 출력 기대
curl -s -w "\nHTTP Status: %{http_code}\n" \
  "https://homelab-1.taild94cc1.ts.net/api/v1/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```
