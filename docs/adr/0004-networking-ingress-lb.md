# ADR 0004: CNI, Gateway, LoadBalancer 선택

## 상태

채택.

## 맥락

현재 클러스터는 VLAN20(`10.0.20.0/24`)에 VM 노드를 배치한다. Kubernetes API VIP는
`10.0.20.100`, LoadBalancer pool은 `10.0.20.240/29`다.

요구사항:

- 홈 네트워크에서 앱에 안정적으로 접근한다.
- 클라우드 LoadBalancer가 없는 bare-metal/private-cloud 환경에서 동작한다.
- 추후 BGP, TLS, 외부 DNS로 확장할 수 있어야 한다.

## 옵션

| 주제 | 옵션 | 장점 | 단점 |
| --- | --- | --- | --- |
| CNI | Flannel | 단순 | NetworkPolicy/Gateway/LB 기능은 별도 구성 필요 |
| CNI | Calico | NetworkPolicy 성숙 | Gateway/LB-IPAM은 별도 구성 필요 |
| CNI | Cilium | eBPF, NetworkPolicy, Gateway API, LB-IPAM 통합 | 학습 곡선 높음 |
| Ingress | NodePort | 단순 | 포트 관리와 라우팅 UX 낮음 |
| Ingress | Ingress Controller | 문서/예제 많음 | Gateway API 대비 role 분리가 약함 |
| Ingress | Gateway API | Gateway/Route 책임 분리 | CRD와 controller 이해 필요 |
| LB 광고 | MetalLB L2 | bare-metal 표준 선택지 | Cilium과 별도 컴포넌트 |
| LB 광고 | Cilium LB-IPAM + L2 | Cilium 내 통합 | L2 announcement 기능 이해 필요 |
| LB 광고 | BGP | 라우터 연동 확장성 높음 | 홈 라우터/네트워크 장비 요구 증가 |

## 결정

`Cilium + Gateway API + Cilium LB-IPAM + L2 announcement`를 유지한다.

## 근거

- 단일 물리 호스트와 단일 VLAN 환경에서는 L2 announcement가 BGP보다 운영 부담이 낮다.
- Cilium을 CNI로 쓰면 NetworkPolicy, Gateway API, LB-IPAM을 한 제품 경계 안에서 학습할 수 있다.
- Gateway API는 공유 Gateway와 앱별 HTTPRoute를 분리한다. 앱 추가 시 Gateway를 반복 정의하지 않는다.
- LB pool을 `10.0.20.240/29`로 제한해 노드 IP와 API VIP 영역을 분리한다.
- 추후 라우터가 BGP를 지원하거나 물리 호스트가 늘어나면 BGP 광고로 이전할 수 있다.

## 운영 명세

- Gateway namespace는 `gateway`다.
- Gateway 이름은 `homelab`이다.
- listener는 HTTP `:80` 하나로 시작한다.
- HTTPRoute를 붙일 namespace는 `gateway.networking.k8s.io/route-access=homelab` label을 가져야 한다.
- LB IP pool은 `network/topology.nix`의 `kubernetes.lb_pool`과 일치해야 한다.
- pool 변경 전후 `kubectl get ippools`와 Gateway Service external IP를 확인한다.

## 확장 전략

| 상황 | 변경 |
| --- | --- |
| 내부 앱만 운영 | HTTP Gateway + Tailscale 접근 유지 |
| 개인 도메인 도입 | HTTPS listener, cert-manager, external-dns ADR 작성 |
| 라우터 BGP 가능 | Cilium BGP Control Plane 검토 |
| 물리 호스트 다중화 | L2/BGP failover 동작을 실측 후 선택 |

## 재검토 조건

- L2 announcement가 홈 네트워크 장비와 충돌한다.
- Gateway API controller 동작을 Cilium에서 분리해야 한다.
- 외부 공개 서비스가 생겨 TLS, WAF, 인증 요구가 증가한다.

## 근거 자료

- 로컬: `deploy/k8s/infrastructure/networking/gateway.yaml`, `lb-ippool.yaml`, `l2-announcement.yaml`
- Kubernetes Gateway API: https://kubernetes.io/docs/concepts/services-networking/gateway/
- Cilium Gateway API: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
- Cilium LB-IPAM: https://docs.cilium.io/en/stable/network/lb-ipam/
- Cilium L2 announcements: https://docs.cilium.io/en/stable/network/l2-announcements/
