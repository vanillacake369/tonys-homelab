# vms/ - MicroVM 정의

MicroVM.nix 기반 경량 가상머신 설정입니다.

## 구조

```
vms/
├── vault.nix           # Vault 시크릿 관리
├── jenkins.nix         # Jenkins CI/CD
├── registry.nix        # Docker Registry
├── k8s-master.nix      # Kubernetes Master (kubeadm)
├── k8s-worker-1.nix    # K8s Worker
└── k8s-worker-2.nix    # K8s Worker
```

## VM 구성

### VLAN 10 - Management

| VM | 역할 | vCPU | Memory |
|----|------|------|--------|
| vault | 시크릿 관리 | 2 | 2GB |
| jenkins | CI/CD | 4 | 4GB |

### VLAN 20 - Services

| VM | 역할 | vCPU | Memory |
|----|------|------|--------|
| registry | 컨테이너 레지스트리 | 2 | 2GB |
| k8s-master | K8s Control Plane | 4 | 8GB |
| k8s-worker-1 | K8s Worker | 8 | 16GB |
| k8s-worker-2 | K8s Worker | 4 | 8GB |

## 프로파일 시스템

VM은 `lib/domains/packages.nix`의 프로파일에 따라 패키지가 주입됩니다:

- **K8s VM** (`k8s-*`): `k8s-node` 프로파일
- **일반 VM**: `server` 프로파일

프로파일 적용은 `lib/mk-microvms.nix`에서 자동 처리됩니다.

## Kubernetes (kubeadm)

VM 내 K8s 설정은 `modules/nixos/k8s-kubeadm-base.nix` 모듈 사용:

```bash
# Master 초기화
kubeadm init --pod-network-cidr=10.244.0.0/16

# Worker 조인
kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

## 스토리지

virtiofs로 호스트-VM 간 디렉토리 공유:

| VM | 호스트 경로 | VM 마운트 |
|----|-------------|-----------|
| vault | /var/lib/microvms/vault/data | /var/lib/vault |
| jenkins | /var/lib/microvms/jenkins/home | /var/lib/jenkins |
| registry | /var/lib/microvms/registry/data | /var/lib/docker-registry |
| k8s-master | /var/lib/microvms/k8s-master/etcd | /var/lib/etcd |

## 관리 명령어

```bash
# VM 상태
just vm-status

# SSH 접속
just vm-ssh-vault
just vm-ssh-k8s-master

# 시작/중지
just vm-start vault
just vm-stop vault
```
