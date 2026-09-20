# Architecture Decision Records

이 디렉토리는 홈랩 플랫폼의 주요 선택지를 기록한다. 목적은 "현재 무엇을 쓰는가"보다
"어떤 선택지 중 왜 이 선택을 했는가"를 남기는 것이다.

현재 전제:

- 물리 failure domain 은 `homelab-1` 단일 머신이다.
- Kubernetes 는 해당 물리 호스트 위의 libvirt VM 3대(`1 master + 2 workers`)로 구성한다.
- 따라서 논리 노드는 3개지만, 전원/디스크/메인보드 장애 기준으로는 싱글 호스트 홈랩이다.
- 앱 배포 플랫폼은 학습 가능성과 운영 가능성을 동시에 만족해야 한다.

## ADR 목록

| ADR | 주제 | 현재 선택 |
| --- | --- | --- |
| [0001](0001-cue-platform-renderer.md) | CUE 기반 앱 렌더러 | 채택, 신규 확장은 보류 |
| [0002](0002-homelab-layering.md) | 홈랩 레이어 경계 | NixOS/libvirt -> kubeadm/Cilium -> Flux/Kustomize |
| [0003](0003-kubernetes-bootstrap.md) | Kubernetes 부트스트랩 | kubeadm + Ansible |
| [0004](0004-networking-ingress-lb.md) | CNI, Gateway, LoadBalancer | Cilium Gateway API + LB-IPAM + L2 announcement |
| [0005](0005-storage-strategy.md) | 스토리지 | local-path-provisioner 우선, Ceph 보류 |
| [0006](0006-app-deployment-contract.md) | 앱 배포 contract | raw manifest 우선, CUE는 제한적 유지 |
| [0007](0007-policy-strategy.md) | 정책/가드레일 | 로컬 검증 + CUE shallow schema |
| [0008](0008-cicd-and-image-delivery.md) | CI/CD와 이미지 배포 | 로컬 검증 + GitOps reconcile, 원격 CI 보류 |
| [0009](0009-dns-ca-and-tls.md) | DNS, CA, TLS | Tailscale 우선, cert-manager/external-dns 보류 |

## 작성 규칙

- 결정은 현재 하드웨어와 다음 확장 단계에 대해 동시에 설명한다.
- 옵션은 최소 3개를 비교한다.
- 재검토 조건을 명시한다.
- 공식 문서 또는 로컬 파일 근거를 남긴다.
