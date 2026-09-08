# ADR 0003: Kubernetes 부트스트랩 방식

## 상태

채택.

## 맥락

현재 구성은 NixOS VM 위에 kubeadm으로 Kubernetes를 구성하고, Ansible이 init/join/verify를
오케스트레이션한다. Cilium은 bootstrap 과정에서 Helm으로 설치한다.

현재 하드웨어 전제:

- 물리 호스트는 1대다.
- Kubernetes 논리 노드는 VM 3대다.
- 물리 HA보다 Kubernetes 구성요소 학습과 재현 가능한 재설치가 우선이다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| k3d | Docker 안에 k3s cluster 생성 | 학습/실험 속도 최고 | 운영 홈랩 네트워크, VM, 실제 노드 장애 모델과 다름 |
| k3s | 경량 Kubernetes 배포판 | 설치 단순, 홈랩에 적합 | kubeadm/control-plane 세부 학습 표면 감소 |
| kubeadm | upstream Kubernetes bootstrap 도구 | 인증서, control-plane, join 흐름 학습에 적합 | 직접 관리할 항목이 많음 |
| Talos | Kubernetes 전용 immutable OS | 운영 단순, API 기반 관리 | NixOS/libvirt 기반과 방향 충돌 |
| managed Kubernetes | 클라우드 제공 cluster | 운영 부담 최소 | 홈랩 네트워크/storage 학습 목표와 충돌 |

## 결정

운영 홈랩은 `kubeadm + Ansible`을 유지한다. k3d는 학습 전용으로만 사용한다.

## 근거

- 목표가 "앱을 올릴 수 있는 홈랩 cluster"와 "기초 개념 재학습"을 동시에 포함한다.
- k3d는 Docker volume/network, Service, Deployment, PVC, Gateway 흐름을 빠르게 실험하는 데 적합하다.
- 운영 repo는 실제 VM IP, VLAN, Cilium, Flux, local-path storage를 다룬다.
- kubeadm은 인증서, API server endpoint, join token, CNI 설치 순서를 드러낸다.
- 단일 물리 호스트에서는 k3s의 운영 단순성이 유리하지만, 현재 학습 목표에서는 kubeadm의 명시성이 더 중요하다.

## 운영 명세

- `network/topology.nix`가 Kubernetes version, Pod CIDR, Service CIDR, API VIP, Cilium version을 가진다.
- `ansible/inventory.nix`가 topology를 Ansible inventory로 변환한다.
- `ansible/site.yml`과 role task가 kubeadm init/join/verify를 실행한다.
- CNI는 kubeadm 이후 Cilium Helm chart로 설치한다.
- reset은 destructive 작업이므로 `CONFIRM_RESET=homelab` guard를 유지한다.

## 확장 전략

| 상황 | 판단 |
| --- | --- |
| 물리 호스트 1대 유지 | kubeadm 유지, HA 주장은 하지 않음 |
| 물리 호스트 2-3대 | stacked etcd HA 또는 external etcd 재평가 |
| 운영 단순성이 학습보다 중요 | k3s 전환 ADR 작성 |
| OS를 Kubernetes 전용으로 전환 | Talos PoC 후 별도 ADR 작성 |

## 재검토 조건

- kubeadm bootstrap 실패 복구 비용이 반복적으로 높다.
- Kubernetes 내부 학습보다 앱 운영 속도가 더 중요해진다.
- 물리 호스트가 3대 이상이 되어 진짜 HA control-plane을 구성할 수 있다.

## 근거 자료

- 로컬: `ansible/README.md`, `ansible/group_vars/all.yml`, `network/topology.nix`
- kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- k3s: https://docs.k3s.io/
- k3s HA: https://docs.k3s.io/installation/ha/
