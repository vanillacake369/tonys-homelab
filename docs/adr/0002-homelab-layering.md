# ADR 0002: 홈랩 플랫폼 레이어 경계

## 상태

채택.

## 맥락

현재 홈랩은 `homelab-1` 물리 호스트 위에 libvirt VM 3대를 올리고, 그 VM들에 Kubernetes
클러스터를 구성한다. 로컬 근거는 `network/topology.nix`, `nodes/physical/homelab-1.nix`,
`README.md`다.

중요한 제약:

- 물리 failure domain 은 단일 호스트다.
- VM은 Kubernetes 개념 학습과 노드 분리를 제공하지만 물리 HA를 제공하지 않는다.
- 저장소는 인프라 생성, 클러스터 부트스트랩, 앱 배포, 정책을 모두 포함한다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| 단일 스크립트 | shell/just 중심으로 모든 것을 순서 실행 | 이해 쉬움, 빠른 수정 | 상태 drift 추적 약함, 확장 시 파편화 |
| Terraform/OpenTofu + Ansible | VM/네트워크는 Terraform, OS/K8s는 Ansible | 업계 패턴과 유사 | NixOS 선언성과 중복, libvirt/provider 상태 관리 증가 |
| NixOS/libvirt + Ansible + GitOps | OS/VM은 Nix, K8s bootstrap은 Ansible, 앱은 GitOps | 현재 repo와 일치, 선언적 재현성 높음 | 도구 수가 많아 온보딩 비용 큼 |
| Talos/Kubernetes appliance | OS까지 Kubernetes 전용으로 단순화 | K8s 운영면 단순 | NixOS 학습/호스트 자동화와 충돌 |

## 결정

현재 레이어는 유지한다.

```text
physical host
-> NixOS host config
-> libvirt VM config
-> kubeadm cluster bootstrap
-> Cilium/Gateway/storage infrastructure
-> Flux/Kustomize app delivery
-> optional platform renderer
```

## 근거

- 단일 물리 호스트에서는 물리 HA가 불가능하다. 따라서 먼저 재현성과 학습 가능성을 최적화한다.
- NixOS는 host/VM OS 상태를 선언적으로 재생성하는 데 적합하다.
- Ansible은 kubeadm init/join 같은 순차 bootstrap 작업을 명시하기에 적합하다.
- GitOps는 클러스터가 뜬 뒤의 Kubernetes object 수렴을 OS bootstrap과 분리한다.
- CUE renderer 같은 상위 추상화는 앱 패턴이 반복된 뒤에만 확장한다.

## 확장 전략

| 확장 단계 | 변경 |
| --- | --- |
| 앱 1-3개 | raw manifest/Kustomize로 직접 운영 |
| 앱 패턴 반복 확인 | CUE renderer 재평가 |
| 물리 호스트 2대 이상 | storage, control-plane HA, LB 광고 방식을 재검토 |
| 외부 사용자 접근 | DNS, TLS, 인증, 백업 정책을 별도 ADR로 분리 |

## 재검토 조건

- 물리 호스트가 2대 이상이 된다.
- VM 대신 bare-metal Kubernetes가 필요해진다.
- NixOS 유지보다 Kubernetes appliance 운영이 더 중요해진다.
- 앱 배포보다 클러스터 bootstrap 유지 비용이 더 커진다.

## 근거 자료

- 로컬: `README.md`, `network/topology.nix`, `nodes/physical/homelab-1.nix`
- Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- Flux concepts: https://fluxcd.io/flux/concepts/
