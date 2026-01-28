# Hybrid K8s Cluster 구현 계획 (kubeadm 기반)

## 개요

AMD Hawk Point iGPU (Radeon 780M)의 VM passthrough 한계로 인해, **호스트에서 직접 GPU를 활용**하는 Hybrid Cluster 구성을 진행합니다.

**핵심 변경: NixOS `easyCerts` → kubeadm 기반으로 전환**

### 왜 kubeadm인가?

| 항목 | NixOS easyCerts | kubeadm |
|------|-----------------|---------|
| 인증서 관리 | cfssl/certmgr 자동 | kubeadm 자동 |
| 부팅 순서 의존성 | 높음 (cfssl 서버 필요) | 낮음 (init 후 join) |
| 노드 추가 | 복잡 (CA 공유 필요) | 간단 (토큰 기반) |
| 문서/커뮤니티 | NixOS 특화 | 업계 표준 |
| Hybrid 구성 | 어려움 | 쉬움 |

```mermaid
flowchart TB
    subgraph Host["호스트 (homelab) - Bare Metal"]
        GPU["AMD 780M iGPU<br/>ROCm/OpenCL"]
        K8S_HOST["K8s Worker Node<br/>(GPU 워크로드)"]
        OLLAMA["Ollama / LocalAI<br/>LLM 추론"]
    end

    subgraph VMs["MicroVMs"]
        MASTER["k8s-master<br/>Control Plane"]
        WORKER1["k8s-worker-1<br/>(CPU only)"]
        WORKER2["k8s-worker-2<br/>(CPU only)"]
    end

    subgraph Cluster["K8s Cluster (kubeadm)"]
        API["API Server"]
    end

    MASTER --> API
    K8S_HOST --> |"kubeadm join"| API
    WORKER1 --> |"kubeadm join"| API
    WORKER2 --> |"kubeadm join"| API
    GPU --> K8S_HOST
    K8S_HOST --> OLLAMA

    style GPU fill:#76b900,color:#fff
    style K8S_HOST fill:#326ce5,color:#fff
    style MASTER fill:#326ce5,color:#fff
```

---

## Phase 1: GPU 비활성화 및 정리 ✅ 완료

k8s-worker-1에서 GPU passthrough 설정 제거 완료.

---

## Phase 2: 호스트 AMD GPU 설정 ✅ 완료

`modules/nixos/amdgpu.nix` 생성 완료. ROCm 환경 구성됨.

---

## Phase 3: kubeadm 기반 K8s 클러스터 구성

### 3.1 k8s-base.nix를 kubeadm 호환 모드로 수정

기존 NixOS `services.kubernetes` 대신 kubelet만 활성화하고, kubeadm이 클러스터를 관리합니다.

```nix
# modules/nixos/k8s-kubeadm-base.nix
{ pkgs, lib, ... }: {
  # 커널 모듈 및 sysctl
  boot.kernelModules = [ "overlay" "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  # 컨테이너 런타임
  virtualisation.containerd.enable = true;

  # kubelet 서비스 (kubeadm이 설정 관리)
  services.kubernetes.kubelet = {
    enable = true;
    kubeconfig.server = ""; # kubeadm이 설정
  };

  # kubeadm, kubectl 패키지
  environment.systemPackages = with pkgs; [
    kubernetes  # kubeadm, kubectl, kubelet
    cri-tools   # crictl
    etcd        # etcdctl (디버깅용)
  ];
}
```

### 3.2 k8s-master VM 설정

```nix
# vms/k8s-master.nix
{
  imports = [ ../modules/nixos/k8s-kubeadm-base.nix ];

  # Control plane용 포트 개방
  networking.firewall.allowedTCPPorts = [
    6443  # API server
    2379 2380  # etcd
    10250 10251 10252  # kubelet, scheduler, controller
  ];

  # etcd 데이터 영구 저장
  # (mk-microvms.nix의 mkStorageModule에서 처리)
}
```

### 3.3 k8s-worker VM 설정

```nix
# vms/k8s-worker-*.nix
{
  imports = [ ../modules/nixos/k8s-kubeadm-base.nix ];

  networking.firewall.allowedTCPPorts = [
    10250  # kubelet
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; }  # NodePort
  ];
}
```

### 3.4 호스트 (GPU Worker) 설정

```nix
# modules/nixos/k8s-worker-host.nix
{
  imports = [ ./k8s-kubeadm-base.nix ];

  # 주의: br_netfilter는 MicroVM 브릿지와 충돌
  # 호스트에서는 별도 처리 필요

  # GPU 노드 레이블은 kubeadm join 후 kubectl로 추가
  # kubectl label node homelab gpu=amd node-type=baremetal
}
```

### 3.5 kubeadm 초기화 절차

#### Step 1: k8s-master에서 클러스터 초기화

```bash
# k8s-master VM에서 실행
sudo kubeadm init \
  --apiserver-advertise-address=10.0.20.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12

# kubeconfig 설정
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config

# CNI (Flannel) 설치
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# join 토큰 생성
kubeadm token create --print-join-command
```

#### Step 2: Worker 노드 join

```bash
# 각 worker에서 실행 (VM 및 호스트)
sudo kubeadm join 10.0.20.10:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

#### Step 3: 호스트 GPU 노드 레이블

```bash
# k8s-master에서 실행
kubectl label node homelab gpu=amd node-type=baremetal
```

### 확인 명령어

```bash
# 노드 상태
kubectl get nodes -o wide

# 노드 레이블
kubectl get nodes --show-labels

# 시스템 파드
kubectl get pods -n kube-system
```

---

## Phase 3.5: kubelet 영속 스토리지 (qcow2 블록 디바이스)

### 배경
- `/var/lib/kubelet`을 virtiofs로 마운트하면 cAdvisor 호환성 문제로 kubelet 크래시
- tmpfs에 두면 VM 재시작 시 소실되어 클러스터가 깨짐
- qcow2 블록 디바이스를 사용하여 실제 파일시스템으로 마운트

### 구현
1. K8s VM에 qcow2 볼륨 추가 (2GB, `/var/lib/kubelet` 마운트)
2. mkK8sStorageModule에서 `microvm.volumes` 설정
3. 기존 backup/restore systemd 서비스 제거

### 변경 파일
| 파일 | 변경 내용 |
|------|----------|
| `lib/domains/vms.nix` | K8s VM에 kubeletVolume 속성 추가 |
| `lib/adapters/microvms.nix` | mkK8sStorageModule에 microvm.volumes 추가 |
| `modules/nixos/k8s-kubeadm-base.nix` | backup/restore 서비스 제거, 의존성 정리 |
| `modules/nixos/microvm-storage.nix` | 주석 업데이트 |

---

## Phase 4: GPU 워크로드 배포

### Ollama 배포 (GPU 노드 타겟팅)

```yaml
# k8s/ollama.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      nodeSelector:
        gpu: amd
        node-type: baremetal
      containers:
      - name: ollama
        image: ollama/ollama:rocm
        ports:
        - containerPort: 11434
        volumeMounts:
        - name: ollama-data
          mountPath: /root/.ollama
        securityContext:
          privileged: true
      volumes:
      - name: ollama-data
        hostPath:
          path: /var/lib/ollama
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
spec:
  type: NodePort
  ports:
  - port: 11434
    nodePort: 31434
  selector:
    app: ollama
```

### 확인 명령어

```bash
# Ollama Pod 상태
kubectl get pods -l app=ollama -o wide

# GPU 사용 확인 (호스트에서)
rocm-smi

# Ollama 테스트
curl http://10.0.20.5:31434/api/tags
```

---

## Phase 5: 네트워크 및 보안 최적화

### 호스트-VM 네트워크 고려사항

```mermaid
flowchart TB
    subgraph Host["호스트 네트워크"]
        BR["vmbr0 (Bridge)"]
        VLAN10["VLAN 10<br/>Management"]
        VLAN20["VLAN 20<br/>Services"]
    end

    subgraph K8s["K8s 네트워크"]
        POD["Pod Network<br/>10.244.0.0/16"]
        SVC["Service Network<br/>10.96.0.0/12"]
    end

    BR --> VLAN10
    BR --> VLAN20
    VLAN20 --> POD
    POD --> SVC
```

### 주의: 호스트의 br_netfilter

호스트에서 `br_netfilter`를 활성화하면 MicroVM 브릿지 트래픽에 iptables가 적용되어 VM 통신이 차단될 수 있습니다.

**해결책:**
- 호스트에서는 `br_netfilter` 비활성화
- 또는 iptables에서 브릿지 트래픽 허용 규칙 추가

---

## 체크리스트

### Phase 1: GPU 비활성화 ✅
- [x] `homelab-constants.nix`에서 `gpu.enable = false`
- [x] VFIO 관련 설정 제거
- [x] VM 정상 작동 확인

### Phase 2: 호스트 GPU 설정 ✅
- [x] `modules/nixos/amdgpu.nix` 생성
- [x] ROCm 패키지 설치
- [ ] `rocm-smi` 테스트 (배포 후)

### Phase 3: kubeadm 클러스터
- [x] `k8s-kubeadm-base.nix` 생성
- [x] k8s-master 설정 수정
- [x] k8s-worker 설정 수정
- [x] 호스트 설정 수정
- [ ] 배포
- [ ] kubeadm init (master)
- [ ] kubeadm join (workers + host)
- [ ] CNI 설치 (Flannel)
- [ ] `kubectl get nodes` 확인

### Phase 3.5: kubelet 영속 스토리지
- [x] vms.nix에 kubeletVolume 정의
- [x] microvms.nix 어댑터에 볼륨 마운트 추가
- [x] k8s-kubeadm-base.nix에서 backup/restore 제거
- [ ] `just build all`로 빌드 확인
- [ ] 배포 후 VM 재시작 시 kubelet 유지 확인
- [ ] `kubectl get nodes` 정상 확인

### Phase 4: GPU 워크로드
- [ ] Ollama Deployment 배포
- [ ] GPU 사용 확인
- [ ] LLM 추론 테스트

### Phase 5: 최적화
- [ ] 네트워크 토폴로지 검토
- [ ] 방화벽 규칙 정리
- [ ] 호스트 br_netfilter 문제 해결

---

## 변경 이력

| 날짜 | 내용 |
|------|------|
| 2026-01-27 | 초안 작성 - GPU passthrough 실패로 인한 Hybrid 구성 계획 |
| 2026-01-27 | kubeadm 기반으로 전환 - NixOS easyCerts 복잡성 해결 |
| 2026-01-28 | Phase 3.5 추가 - kubelet qcow2 블록 디바이스 영속화 |
