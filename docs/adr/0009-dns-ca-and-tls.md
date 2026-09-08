# ADR 0009: DNS, CA, TLS 자동화

## 상태

채택.

## 맥락

현재 Gateway는 HTTP `:80`만 열고, 주석상 TLS는 Tailscale Serve 또는 추후 개인 도메인 도입 후
재검토하는 경계로 둔다. 현재 홈랩은 내부/개인 접근이 우선이고, 공개 인터넷 서비스는 전제가 아니다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| hosts 파일/수동 DNS | 클라이언트에서 직접 이름 매핑 | 단순 | 장비마다 반복 |
| Tailscale MagicDNS | tailnet 내부 이름 사용 | 외부 공개 없이 접근 쉬움 | public domain/TLS와 다름 |
| Tailscale Serve/Funnel | Tailscale 경로에서 TLS/공개 노출 | 홈랩 방화벽 노출 감소 | Kubernetes Gateway TLS 학습 표면 감소 |
| cert-manager self-signed/CA | 내부 CA로 인증서 발급 | CA 학습에 적합 | 클라이언트 trust 배포 필요 |
| cert-manager ACME HTTP01 | Let's Encrypt HTTP 검증 | 표준 public TLS | 외부에서 HTTP 도달 가능해야 함 |
| cert-manager ACME DNS01 | DNS provider API로 검증 | 내부 서비스도 public cert 가능 | DNS provider credential 필요 |
| external-dns | Kubernetes resource에서 DNS record 자동화 | record drift 감소 | provider credential과 blast radius 증가 |

## 결정

현재는 `Tailscale/MagicDNS 우선`으로 둔다. cert-manager와 external-dns는 보류한다.

## 근거

- 현재 앱은 개인 홈랩 접근이 목표이며, 공개 인터넷 노출은 필수 요구가 아니다.
- 단일 물리 호스트에서는 TLS 자동화보다 라우팅, Service, HTTPRoute, NetworkPolicy 학습이 우선이다.
- cert-manager와 external-dns는 DNS provider credential을 cluster에 넣어야 한다.
- 내부 CA는 학습 가치가 있지만, 클라이언트 trust 배포와 인증서 갱신 절차가 별도 운영 책임이 된다.
- 개인 도메인 도입 전에는 HTTP Gateway + Tailscale 접근이 가장 작은 운영면을 가진다.

## 운영 명세

- Gateway는 HTTP listener 하나로 유지한다.
- HTTPRoute host/path는 앱 라우팅 의도를 표현하되, TLS contract로 간주하지 않는다.
- public DNS record는 수동으로만 관리한다.
- cluster 안에 DNS provider credential을 넣지 않는다.
- cert-manager 도입 전 CA/DNS/TLS ADR을 업데이트한다.

## 확장 전략

| 상황 | 선택 |
| --- | --- |
| tailnet 내부 개인 접근 | MagicDNS 유지 |
| 내부 TLS 학습 | cert-manager CA Issuer PoC |
| 개인 도메인 + 내부 서비스 | ACME DNS01 검토 |
| 공개 웹 서비스 | cert-manager + Gateway TLS + external-dns 검토 |
| 여러 앱 hostname 증가 | external-dns 도입 조건 충족 |

## 재검토 조건

- 개인 도메인을 Kubernetes Gateway에 연결한다.
- 브라우저 경고 없는 HTTPS가 앱 요구사항이 된다.
- hostname이 3개 이상이고 수동 DNS 관리가 반복된다.
- DNS provider API credential을 SOPS/Flux로 안전하게 관리할 준비가 된다.

## 근거 자료

- 로컬: `deploy/k8s/infrastructure/networking/gateway.yaml`, `docs/runbooks/magicdns-gitops-onboarding.md`
- cert-manager: https://cert-manager.io/docs/
- cert-manager CA issuer: https://cert-manager.io/docs/configuration/ca/
- ExternalDNS: https://kubernetes-sigs.github.io/external-dns/
- Kubernetes Gateway API: https://kubernetes.io/docs/concepts/services-networking/gateway/
