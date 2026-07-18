# Refactor Points - 2026-07-18

## 범위

- 대상: NixOS node cluster, Kubernetes bootstrap, GitOps/platform manifest tree.
- 관점: single-node-ish 구성에서 n-node cluster로 확장할 때 깨질 SSoT, 파일 경계, 운영 실패 모드.
- 원칙: DRY, YAGNI, SSoT, ZII, RAII, Pool/Arena. 말은 거창하지만 핵심은 단순하다. 상태를 한 곳에 두고, 생성물과 선언을 섞지 않고, 사람이 기억해야 하는 규칙을 줄이는 것이다.

## 현재 결론

현재 구조는 "작동하는 homelab"으로는 나쁘지 않다. 그러나 n-node cluster의 베이스로 쓰기에는 몇 군데가 너무 빨리 썩는다.

가장 먼저 고칠 것은 Kubernetes YAML 미학이 아니라 node ownership model이다. VM이 어느 physical host에 속하는지, 어떤 네트워크에 붙는지, 어떤 cluster role을 갖는지가 단일 데이터 모델로 강제되어야 한다. 지금은 `network/topology.nix`가 그 역할을 하려 하지만, 일부 값은 Nix overlay, Ansible vars, SSH config, K8s YAML, README로 새고 있다.

## 주요 발견

### 1. VM ownership이 host별로 닫혀 있지 않다

`nodes/physical/homelab-1.nix`는 `mk-libvirt.nix`에 `network.vms` 전체를 넘긴다. `mk-libvirt.nix`는 받은 VM 전부를 libvirt domain service로 만든다.

단일 physical host에서는 문제처럼 보이지 않는다. n-physical-host가 되면 각 host가 전체 VM을 자기 VM처럼 정의하는 구조로 쉽게 변한다. 컴퓨터는 "이건 homelab-1 전용일 거야" 같은 분위기를 읽지 않는다.

권장:

- `topology.vms`에는 `parentHost`만 둔다.
- `host` alias는 제거한다.
- `vmsForHost = hostName: filterAttrs (_: vm: vm.parentHost == hostName) topology.vms` 같은 helper를 둔다.
- 각 physical node는 자기 `hostName`에 해당하는 VM만 libvirt에 넘긴다.

### 2. topology가 SSoT가 되려다 말았다

`network/topology.nix`에는 K8s version, Cilium Helm version, API VIP, LB pool, VM IP/MAC/resource가 있다. 방향은 맞다.

문제는 같은 정보가 다른 계층에도 남아 있다는 점이다.

- K8s version: topology와 `atoms/k8s/k8s-distro-compat.overlay.nix`.
- Cilium 관련 값: topology, `atoms/k8s/cni-cilium.overlay.nix`, Ansible vars.
- VM IP: topology, `nodes/vms/*.nix`, `atoms/network/ssh-client.nix`.
- LB pool: topology와 `deploy/k8s/infrastructure/networking/lb-ippool.yaml`.
- app external host: app configmap, CUE app, runbook에 분산.

테스트가 일부 drift를 잡고 있지만, 테스트는 SSoT가 아니다. 테스트는 사고 감지기지 설계 자체가 아니다.

권장:

- topology를 "cluster inventory SSoT"로 확정한다.
- generated artifact를 둘 거면 generated임을 명확히 한다.
- hand-written manifest로 남길 값은 topology와 비교하는 drift test를 둔다.
- overlay version은 string parsing test보다 Nix data 주입 구조가 낫다.

### 3. VM node 파일이 너무 비슷하다

`nodes/vms/k8s-master-1.nix`, `k8s-worker-1.nix`, `k8s-worker-2.nix`는 거의 같은 구조다.

지금 중복은 작아 보인다. 그러나 worker 6대, master 3대가 되면 이 중복은 운영자가 실수할 공간이 된다. IP 하나 틀리고, gateway 하나 남고, role 하나 틀리는 식이다. 대개 장애는 이런 평범한 중복에서 온다.

권장:

- `lib/mk-k8s-vm-node.nix` 같은 helper로 공통 boot, filesystem, systemd-networkd, node contract를 생성한다.
- role별 차이는 `role = "k8s-master" | "k8s-worker"`에서 import가 갈라지게 한다.
- 예외가 생길 때만 VM 파일에서 override한다.

### 4. kube-vip interface detection이 네트워크 모델을 우회한다

Ansible bootstrap은 `ip -o -4 addr show | grep '10\.0\.20\.'` 방식으로 kube-vip interface를 찾는다.

이건 지금 VLAN20에서는 통한다. 하지만 services CIDR이 바뀌거나 multi-network가 되면 깨진다. 그리고 깨질 때는 예쁘게 깨지지 않는다. VIP가 엉뚱한 interface에 붙거나 아예 붙지 않는다.

권장:

- Ansible inventory가 VM의 `network`, parent host VLAN, service CIDR을 넘긴다.
- 가능하면 interface name도 NixOS node config에서 선언하거나 생성한다.
- grep 기반 탐지는 fallback 정도로만 둔다.

### 5. local-path storage는 n-node readiness와 충돌한다

BookOrbit app과 Postgres는 `k8s-worker-1`에 nodeSelector로 고정되어 있고, local-path StorageClass를 쓴다.

이 선택은 틀린 것이 아니다. 오히려 단일 디스크 homelab에서는 정직한 선택이다. 문제는 이 상태를 "n-node cluster 준비"라고 부르면 거짓말이 된다는 점이다. compute node는 늘어나도 stateful workload는 특정 worker 하나에 묶인다.

선택지는 세 가지다.

1. local-path 유지: 가장 단순하고 빠르다. 대신 pet node 장애를 받아들인다.
2. local-path + 명시적 data node pool: 덜 거짓말한다. storage node를 label/taint로 모델링한다.
3. distributed storage 도입: Longhorn, Rook/Ceph, OpenEBS, democratic-csi/ZFS 계열. 운영 복잡도가 크게 올라간다.

현 단계 추천은 2번이다. homelab에서 Ceph부터 들이미는 건 보통 과하다. 디스크, 네트워크, 복구 절차가 준비되지 않은 분산 스토리지는 "고가용성"이 아니라 장애 표면적 증가다.

## 질문별 판단

### 문서를 줄이고 code/state가 말하게 하는 편향은 타당한가?

부분적으로 타당하다. 하지만 "문서가 불필요하다"는 결론은 과하다.

좋은 방향:

- 현재 상태, inventory, topology, rendered manifest는 코드가 말해야 한다.
- README에 IP, node 수, version 같은 live state를 손으로 반복하지 않는다.
- runbook은 명령과 복구 절차처럼 코드가 표현하지 못하는 operational knowledge만 남긴다.

나쁜 방향:

- ADR, runbook, migration note까지 없애는 것.
- 왜 이런 구조인지, 실패 시 어디부터 볼지, destructive command의 의미를 코드만 보고 추론하게 하는 것.

권장 bias:

- docs as interface, not docs as database.
- 상태 데이터는 코드와 generated output으로.
- 이유와 운영 절차는 짧은 문서로.
- README는 architecture snapshot이 아니라 entrypoint와 command index 정도로 축소.

즉 "문서 제거"가 아니라 "문서에서 상태를 제거"가 맞다.

### K8s 관련 파일 트리는 어떻게 잡는 게 좋은가?

현재 `deploy/gitops/`, `deploy/k8s/`, `deploy/platform/`, `policy/`, `scripts/`가 나뉘어 있는데, 추상화 레벨이 섞여 보인다.

내 추천은 `/deploy` 아래로 수렴시키는 것이다. 이름은 중요하지 않다. 중요한 것은 계층이다.

제안 구조:

```text
deploy/
  clusters/
    homelab/
      flux-system/
      root/
      kustomization.yaml
  infra/
    networking/
    storage/
    registry/
    kyverno/
  apps/
    bookorbit/
  deploy/platform/
    api/
    profiles/
    apps/
    render/
    generated/
  policy/
    kyverno/
  tools/
    platform-render.sh
```

더 엄격히 가면:

```text
packages/
  nixos/
  cluster/
    deploy/
    deploy/platform/
    policy/
```

하지만 지금 단계에서는 `/deploy` 하나로 충분하다. "패키지"라는 단어를 쓰기 전에 package boundary가 있어야 한다. API, tests, generated output, release process가 분리되지 않았는데 폴더만 package처럼 만들면 겉멋이다.

권장:

- `k8s`, `gitops`, `policy`, `platform`을 `/deploy` 아래로 모은다.
- CUE platform renderer는 `/deploy/platform` 안에 둔다.
- generated manifests는 `/deploy/platform/generated` 또는 `/deploy/generated/apps`로 둔다.
- cluster entrypoint는 `/deploy/clusters/homelab` 하나로 고정한다.
- hand-written app과 generated app을 섞지 않는다.

### Ansible + Nix atoms/k8s 조합은 최선인가?

최선은 아니다. 하지만 현재 제약에서는 꽤 현실적인 조합이다.

NixOS가 잘하는 일:

- kernel modules, sysctl, containerd, kubelet systemd unit.
- filesystem paths, tmpfiles, packages, users, secrets path.
- node-level immutable-ish baseline.

Ansible이 하고 있는 일:

- kubeadm init/join orchestration.
- bootstrap order, token/cert propagation.
- kube-vip, Cilium Helm install.
- state detection and reset.

문제는 두 도구가 같은 경계를 만질 때 생긴다. kubelet, CNI path, `/etc/kubernetes`, kubeadm generated state는 Nix와 Ansible 모두 관심을 갖는다. 여기서 선을 명확히 긋지 않으면 나중에 "누가 이 파일 만들었지?"라는 지루한 탐정놀이가 시작된다.

선택지:

1. NixOS atoms + Ansible kubeadm 유지
    - 장점: 지금 구조와 가장 가깝다. kubeadm HA 흐름을 그대로 쓸 수 있다.
    - 단점: bootstrap state가 imperative하다.
    - 추천도: 현재 최적.

2. NixOS native Kubernetes 모듈로 회귀
    - 장점: 선언형처럼 보인다.
    - 단점: kubeadm ecosystem, Cilium, kube-vip, HA bootstrap과 어긋나기 쉽다.
    - 추천도: 낮음.

3. Talos로 Kubernetes node OS 교체
    - 장점: K8s node 운영 모델이 매우 깔끔하다.
    - 단점: NixOS homelab 실험장의 의미가 줄고, 현재 NixOS module 자산을 버린다.
    - 추천도: 운영 K8s만 중요하면 강함. NixOS 학습/통합이 중요하면 과함.

4. k3s, k0s 같은 경량 distro로 전환
    - 장점: bootstrap이 단순하다.
    - 단점: kubeadm 표준 HA와 enterprise control plane 학습 가치는 줄어든다.
    - 추천도: homelab 앱 운영 목적이면 좋음. kubeadm/NixOS infra 실험이면 애매함.

5. Cluster API, Kubespray, Terraform 조합
    - 장점: 큰 조직 스타일에 가깝다.
    - 단점: 지금 규모에는 무겁다. 문제보다 도구가 커진다.
    - 추천도: 지금은 보류.

현재 추천은 1번 유지다. 단, 경계를 문서가 아니라 코드 구조로 강제해야 한다.

권장 경계:

- Nix owns node substrate:
    - containerd
    - kubelet unit wrapper
    - kernel/sysctl/cgroup/bpf
    - packages
    - host network
    - secrets mount path
- Ansible owns cluster bootstrap:
    - kubeadm init/join/reset
    - kube-vip bootstrap artifact
    - Cilium installation
    - join token/cert key propagation
- Flux owns cluster steady-state:
    - infrastructure controllers
    - policies
    - applications
    - generated app manifests

이 경계가 지켜지면 Ansible + Nix 조합은 나쁘지 않다. 경계가 흐려지면 최악의 조합이 된다. 둘 다 root 권한으로 "내가 맞다"고 말할 수 있기 때문이다.

## 가장 작은 실행 계획

1. topology schema 정리
    - `host` 제거, `parentHost`만 유지.
    - `cluster`, `network`, `role`, `ip`, `mac`, `tapId`, resource field를 명시 contract로 유지.

2. host별 VM projection 추가
    - `vmsForHost`.
    - physical host libvirt는 자기 VM만 받게 변경.

3. VM node generator 도입
    - `nodes/vms/*.nix`의 반복 boot/filesystem/network block 제거.
    - 예외만 node file에 남김.

4. deploy tree 재배치 설계
    - 먼저 이동표를 작성한다.
    - import path와 just recipe를 같이 바꾼다.
    - 한 번에 semantic change까지 섞지 않는다.

5. Ansible/Nix 경계 테스트 추가
    - topology -> ansible inventory.
    - topology -> libvirt VM ownership.
    - topology -> LB pool drift.
    - topology -> SSH config drift.

6. docs 축소
    - README에서 live state 표와 과한 topology 설명 제거.
    - runbook은 장애 대응 절차만 유지.
    - generated state는 사람이 쓰지 않는다.

## 최종 권고

지금 당장 큰 도구 전환은 하지 않는 편이 낫다. Ansible을 버리고 더 멋진 무언가를 넣으면 잠깐 기분은 좋아지겠지만, 실제 문제인 SSoT 붕괴와 ownership 부재는 그대로 남는다.

먼저 데이터 모델을 단단히 하라. 그 다음 파일 트리를 정리하라. 마지막에 bootstrap 도구를 바꿀지 판단하라.

순서는 이렇다.

```text
topology contract -> host/vm projection -> generated deployment tree -> bootstrap boundary -> optional tool replacement
```

이 순서를 거꾸로 하면 흔한 인프라 리팩터링 쇼가 된다. 폴더는 예뻐졌는데 상태는 더 모호해지는 그 재미없는 종류다.
