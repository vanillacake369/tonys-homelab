# Argo CD pilot adapter

이 디렉터리는 `deploy/k8s/generated/apps/*`를 Argo CD가 소비할 수 있는지 검토하기 위한
초안이다. 현재 운영 reconciler는 Flux이며, 이 파일들은 클러스터 루트
Kustomization에서 참조하지 않는다.

Flux와 Argo CD가 같은 `Namespace`, `Deployment`, `Service`, `HTTPRoute`,
`CiliumNetworkPolicy`를 동시에 reconcile하면 ownership이 충돌한다. Argo pilot을
진행할 때는 먼저 Flux 쪽 Kustomization을 suspend하거나 path ownership을 분리해야 한다.
