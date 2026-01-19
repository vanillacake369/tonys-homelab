# vms/ - MicroVM 정의

MicroVM.nix 기반 경량 가상머신 설정입니다.

## 디렉토리 구조

```
vms/
├── vault.nix           # Vault 시크릿 관리
├── jenkins.nix         # Jenkins CI/CD
├── registry.nix        # Docker Registry
├── k8s-master.nix      # Kubernetes Master
├── k8s-worker-1.nix    # K8s Worker (GPU)
└── k8s-worker-2.nix    # K8s Worker
```

## VM 아키텍처

### MicroVM.nix 개요

MicroVM.nix는 QEMU 기반 경량 가상화 솔루션으로:

- NixOS 설정으로 VM 정의
- virtiofs로 호스트-VM 스토리지 공유
- TAP 인터페이스로 네트워크 연결
- systemd 서비스로 VM 라이프사이클 관리

### 공통 설정 패턴

모든 VM은 다음 패턴을 따릅니다:

```nix
{
  microvm = {
    hypervisor = "qemu";
    vcpu = <CPU 코어 수>;
    mem = <메모리 MB>;

    interfaces = [{
      type = "tap";
      id = "<TAP 인터페이스 ID>";
      mac = "<MAC 주소>";
    }];

    shares = [{
      source = "<호스트 경로>";
      mountPoint = "<VM 내 마운트>";
      tag = "<virtiofs 태그>";
    }];
  };
}
```

## VM 상세 스펙

### VLAN 10 - Management

#### vault.nix

HashiCorp Vault 시크릿 관리 서버

| 항목      | 값         |
| --------- | ---------- |
| IP        | 10.xxx.xxx.xxx |
| vCPU      | 2          |
| Memory    | 2GB        |
| TAP       | vm-vault   |
| vsock CID | 100        |

**포트:**

- 22 (SSH)
- 8200 (Vault API/UI)

**스토리지:**

- 호스트: `/var/lib/microvms/vault/data`
- VM: `/var/lib/vault`

**용도:**

- 애플리케이션 시크릿 저장
- PKI/인증서 관리
- 동적 자격 증명 발급

---

#### jenkins.nix

Jenkins CI/CD 서버

| 항목      | 값         |
| --------- | ---------- |
| IP        | 10.xxx.xxx.xxx |
| vCPU      | 4          |
| Memory    | 4GB        |
| TAP       | vm-jenkins |
| vsock CID | 101        |

**포트:**

- 22 (SSH)
- 8080 (Web UI)

**스토리지:**

- 호스트: `/var/lib/microvms/jenkins/home`
- VM: `/var/lib/jenkins`

**용도:**

- CI/CD 파이프라인 실행
- 컨테이너 이미지 빌드
- 자동화 작업

---

### VLAN 20 - Services

#### registry.nix

Docker Registry 서버

| 항목      | 값          |
| --------- | ----------- |
| IP        | 10.xxx.xxx.xxx  |
| vCPU      | 2           |
| Memory    | 2GB         |
| TAP       | vm-registry |
| vsock CID | 102         |

**포트:**

- 22 (SSH)
- 5000 (Registry API)

**스토리지:**

- 호스트: `/var/lib/microvms/registry/data`
- VM: `/var/lib/docker-registry`

**용도:**

- 프라이빗 컨테이너 이미지 저장
- K8s 클러스터 이미지 공급

---

#### k8s-master.nix

Kubernetes Control Plane

| 항목      | 값            |
| --------- | ------------- |
| IP        | 10.xxx.xxx.xxx    |
| vCPU      | 4             |
| Memory    | 8GB           |
| TAP       | vm-k8s-master |
| vsock CID | 103           |

**포트:**

- 22 (SSH)
- 6443 (API Server)
- 2379 (etcd client)
- 2380 (etcd peer)
- 10250 (kubelet)
- 10251 (scheduler)
- 10252 (controller-manager)

**스토리지:**

- 호스트: `/var/lib/microvms/k8s-master/etcd`
- VM: `/var/lib/etcd`

**용도:**

- K8s API Server
- etcd 클러스터 (단일 노드)
- 스케줄러 및 컨트롤러

---

#### k8s-worker-1.nix

Kubernetes Worker (GPU 지원)

| 항목      | 값                  |
| --------- | ------------------- |
| IP        | 10.xxx.xxx.xxx          |
| vCPU      | 8                   |
| Memory    | 16GB                |
| TAP       | vm-k8s-worker1      |
| vsock CID | - (GPU passthrough) |

**포트:**

- 22 (SSH)
- 10250 (kubelet)
- 30000-32767 (NodePort)

**스토리지:** 없음 (Stateless)

**특수 설정:**

- GPU passthrough 지원 (VFIO)
- vsock 비활성화 (QEMU 직접 실행)

**용도:**

- GPU 워크로드 실행
- ML/AI 작업

---

#### k8s-worker-2.nix

Kubernetes Worker

| 항목      | 값             |
| --------- | -------------- |
| IP        | 10.xxx.xxx.xxx     |
| vCPU      | 4              |
| Memory    | 8GB            |
| TAP       | vm-k8s-worker2 |
| vsock CID | 104            |

**포트:**

- 22 (SSH)
- 10250 (kubelet)
- 30000-32767 (NodePort)

**스토리지:** 없음 (Stateless)

**용도:**

- 일반 워크로드 실행
- 서비스 Pod 배포

## VM 관리 명령어

### 상태 확인

```bash
# 모든 VM 상태
just vm-status

# 연결 테스트
just vm-ping
```

### 시작/중지

```bash
# 특정 VM 시작
just vm-start vault

# 특정 VM 중지
just vm-stop vault

# 모든 VM 중지
just vm-stop-all

# 재시작
just vm-restart vault
```

### SSH 접속

모든 VM은 호스트를 Jump host로 사용하여 접속합니다.

```bash
# 전용 명령어
just vm-ssh-vault
just vm-ssh-jenkins
just vm-ssh-registry
just vm-ssh-k8s-master
just vm-ssh-k8s-worker1
just vm-ssh-k8s-worker2

# 수동 접속
ssh -J homelab root@10.xxx.xxx.xxx
```

### 로그 확인

```bash
# VM 로그 (follow)
just vm-logs vault

# systemd 서비스 로그
ssh homelab "journalctl -u microvm@vault -f"
```

### 콘솔 접속

```bash
# QEMU 콘솔 (Ctrl-A, X로 종료)
just vm-console vault
```

## 새 VM 추가 가이드

### 1. 상수 정의

`lib/homelab-constants.nix`에 VM 추가:

```nix
vms = {
  my-vm = {
    vlan = "services";        # management 또는 services
    ip = "10.xxx.xxx.xxx0";
    mac = "02:00:00:00:20:99";
    vsockCid = 199;
    vcpu = 2;
    mem = 2047;               # 2048 회피 (QEMU 버그)
    tapId = "vm-myvm";
    hostname = "my-vm";
    ports = {
      ssh = 22;
      app = 8080;
    };
    storage = {
      source = "/var/lib/microvms/my-vm/data";
      mountPoint = "/var/lib/myapp";
      tag = "myvm-storage";
    };
  };
};
```

### 2. VM 설정 파일 생성

`vms/my-vm.nix` 생성:

```nix
{ config, pkgs, lib, ... }:
let
  constants = import ../lib/homelab-constants.nix;
  vmConfig = constants.vms.my-vm;
  vlanConfig = constants.networks.vlans.${vmConfig.vlan};
in {
  microvm = {
    hypervisor = constants.common.hypervisor;
    vcpu = vmConfig.vcpu;
    mem = vmConfig.mem;

    interfaces = [{
      type = "tap";
      id = vmConfig.tapId;
      mac = vmConfig.mac;
    }];

    shares = lib.optional (vmConfig ? storage) {
      source = vmConfig.storage.source;
      mountPoint = vmConfig.storage.mountPoint;
      tag = vmConfig.storage.tag;
      proto = "virtiofs";
    };

    vsock = lib.mkIf (vmConfig ? vsockCid) {
      cid = vmConfig.vsockCid;
    };
  };

  networking = {
    hostName = vmConfig.hostname;
    useNetworkd = true;
    firewall.allowedTCPPorts = lib.attrValues vmConfig.ports;
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Type = "ether";
      address = ["${vmConfig.ip}/${toString vlanConfig.prefixLength}"];
      gateway = [vlanConfig.gateway];
      dns = constants.networks.dns;
    };
  };

  # 추가 서비스 설정...

  system.stateVersion = constants.common.stateVersion;
}
```

### 3. 네트워크 설정 추가

`modules/nixos/network.nix`에 TAP 인터페이스 추가:

```nix
# netdevs에 추가
"25-vm-myvm" = {
  netdevConfig = {
    Name = "vm-myvm";
    Kind = "tap";
  };
  tapConfig.User = "root";
};

# networks에 추가
"30-vm-myvm" = {
  matchConfig.Name = "vm-myvm";
  networkConfig.Bridge = "vmbr0";
  bridgeVLANs = [{
    bridgeVLANConfig = {
      VLAN = 20;  # VLAN ID
      PVID = true;
      EgressUntagged = true;
    };
  }];
};
```

### 4. 스토리지 디렉토리 설정

`modules/nixos/microvm-storage.nix`에 추가:

```nix
systemd.tmpfiles.rules = [
  "d /var/lib/microvms/my-vm/data 0755 root kvm -"
];
```

### 5. 배포

```bash
# 스토리지 디렉토리 생성
just vm-setup-storage

# 배포
just deploy

# VM 상태 확인
just vm-status
```

## 주의사항

### 메모리 설정

- **2048MB 회피**: QEMU hang 버그로 인해 2GB는 `2047`로 설정
- **메모리 오버커밋**: 총 VM 메모리가 호스트 RAM을 초과하지 않도록 주의

### 네트워크

- **MAC 주소**: 충돌 방지를 위해 `02:00:00:00:XX:XX` 형식 사용
- **VLAN 태깅**: PVID 설정으로 VM은 untagged 트래픽 송수신

### 스토리지

- **virtiofs**: 호스트-VM 간 파일 공유에 사용
- **퍼미션**: 호스트 디렉토리는 `root:kvm` 소유, 0755 권한
- **Stateless VM**: k8s-worker는 영구 스토리지 없이 운영

### GPU Passthrough (k8s-worker-1)

- vsock 비활성화 필요
- VFIO 드라이버 바인딩 선행 필요
- IOMMU 그룹 확인 필수
