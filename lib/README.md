# lib/ - 인프라 상수

> [!IMPORTANT]
> 본 시스템은 lib/homelab-constants.nix 를 참고합니다
> [homelab-constants-example.nix](./homelab-constants-example.nix) 를 참고하여 lib/homelab-constants.nix 를 선언해주세요

> [!IMPORTANT]
> 본 인프라 상수는 NixOS Evalution 에 읽혀져 NixOS 에 반영됩니다
> 이에 따라 Runtime 에 동작하는 [sops-nix](https://github.com/Mic92/sops-nix) 는 사용이 불가능합니다.
>
> ```
> graph TD
>     subgraph NixOS_Infrastructure ["NixOS System Lifecycle"]
>
>         subgraph Evaluation ["1. Evaluation (설계 단계)"]
>             direction TB
>             A["Nix Source Codes<br/>(flake.nix, constants.nix)"]
>             B["Nix Evaluator"]
>             A --> B
>             B --> C["Derivations (.drv)<br/>(시스템 설계도)"]
>         end
>
>         subgraph Build ["2. Build (조립 단계)"]
>             direction TB
>             D["Nix Store Builds<br/>(/nix/store/...)"]
>             C --> D
>         end
>
>         subgraph Runtime ["3. Runtime & Activation (실행 단계)"]
>             direction TB
>             E["Activation Scripts<br/>(시스템 활성화)"]
>             F["Systemd Services<br/>(Vault, K8s, etc.)"]
>
>             E --> F
>         end
>
>         %% Connection between stages
>         C --> D
>         D --> E
>
>         %% SOPS-NIX Injection Point
>         S[("sops-nix<br/>복호화 적용")] -- "Runtime 시점에 개입" --> E
>
>     end
>
>     %% Styling
>     style NixOS_Infrastructure fill:#f5f5f5,stroke:#333,stroke-width:3px
>     style Evaluation fill:#fff,stroke:#777
>     style Build fill:#fff,stroke:#777
>     style Runtime fill:#fff,stroke:#777
>     style S fill:#ff9900,stroke:#333,stroke-width:2px,color:#fff
> ```

홈랩 인프라의 **Single Source of Truth**입니다.
모든 하드코딩된 값(IP, VLAN, VM 스펙 등)이 이 디렉토리에 정의됩니다.

## 파일 구조

```
lib/
└── homelab-constants.nix    # 모든 인프라 상수 정의
```

## homelab-constants.nix

### 개요

순수 데이터 파일로, NixOS 모듈 평가 전에 로드됩니다.
재귀 참조 문제 없이 안전하게 모든 곳에서 import할 수 있습니다.

### 구조

```nix
rec {
  networks = { ... };   # 네트워크 토폴로지
  vms = { ... };        # VM 인벤토리
  common = { ... };     # 공통 설정
  host = { ... };       # 호스트 설정
}
```

## 네트워크 토폴로지

### WAN

| 항목       | 값                 |
| ---------- | ------------------ |
| 네트워크   | 192.xxx.xxx.xxx/24 |
| 호스트 IP  | 192.xxx.xxx.xxx    |
| 게이트웨이 | 192.xxx.xxx.xxx    |
| DNS        | 8.8.8.8, 1.1.1.1   |

### VLAN 10 - Management

| 항목       | 값                |
| ---------- | ----------------- |
| ID         | 10                |
| 네트워크   | 10.xxx.xxx.xxx/24 |
| 게이트웨이 | 10.xxx.xxx.xxx    |
| 호스트 IP  | 10.xxx.xxx.xxx    |
| 용도       | Vault, Jenkins    |

### VLAN 20 - Services

| 항목       | 값                |
| ---------- | ----------------- |
| ID         | 20                |
| 네트워크   | 10.xxx.xxx.xxx/24 |
| 게이트웨이 | 10.xxx.xxx.xxx    |
| 호스트 IP  | 10.xxx.xxx.xxx    |
| 용도       | K8s, Registry     |

## VM 인벤토리

### VLAN 10 (Management)

| VM      | IP             | MAC             | vCPU | Memory | vsock CID  | TAP        |
| ------- | -------------- | --------------- | ---- | ------ | ---------- | ---------- |
| vault   | 10.xxx.xxx.xxx | 원하는 MAC 주소 | 2    | 2GB    | 원하는 CID | vm-vault   |
| jenkins | 10.xxx.xxx.xxx | 원하는 MAC 주소 | 4    | 4GB    | 원하는 CID | vm-jenkins |

### VLAN 20 (Services)

| VM           | IP             | MAC             | vCPU | Memory | vsock CID  | TAP            |
| ------------ | -------------- | --------------- | ---- | ------ | ---------- | -------------- |
| registry     | 10.xxx.xxx.xxx | 원하는 MAC 주소 | 2    | 2GB    | 원하는 CID | vm-registry    |
| k8s-master   | 10.xxx.xxx.xxx | 원하는 MAC 주소 | 4    | 8GB    | 원하는 CID | vm-k8s-master  |
| k8s-worker-1 | 10.xxx.xxx.xxx | 원하는 MAC 주소 | 8    | 16GB   | -          | vm-k8s-worker1 |
| k8s-worker-2 | 10.xxx.xxx.xxx | 원하는 MAC 주소 | 4    | 8GB    | 원하는 CID | vm-k8s-worker2 |

**참고:** k8s-worker-1은 GPU passthrough를 위해 vsock을 사용하지 않음

### VM 포트 정의

VM 별로 원하는 포트를 선언합니다.

## 스토리지 매핑

| VM         | 호스트 경로                       | VM 마운트 포인트         | 태그             |
| ---------- | --------------------------------- | ------------------------ | ---------------- |
| vault      | /var/lib/microvms/vault/data      | /var/lib/vault           | vault-storage    |
| jenkins    | /var/lib/microvms/jenkins/home    | /var/lib/jenkins         | jenkins-home     |
| registry   | /var/lib/microvms/registry/data   | /var/lib/docker-registry | registry-storage |
| k8s-master | /var/lib/microvms/k8s-master/etcd | /var/lib/etcd            | k8s-etcd         |

**참고:** k8s-worker-1/2는 stateless로 운영 (스토리지 없음)

## 사용법

### Nix 코드에서 참조

```nix
# flake.nix에서 export
homelabConstants = import ./lib/homelab-constants.nix;

# 다른 모듈에서 사용
{ config, ... }:
let
  constants = import ../lib/homelab-constants.nix;
in {
  networking.hostName = constants.host.hostname;
}
```

### CLI에서 값 확인

```bash
# WAN IP 확인
nix eval --raw .#homelabConstants.networks.wan.host

# VM IP 확인
nix eval --raw .#homelabConstants.vms.vault.ip

# 전체 구조 확인
nix eval .#homelabConstants --json | jq
```

### justfile에서 참조

```just
vault_ip := `nix eval --raw .#homelabConstants.vms.vault.ip`
```

## 값 변경 가이드

### IP 주소 변경

1. `homelab-constants.nix`에서 해당 값 수정
2. `just check`로 검증
3. `just deploy`로 배포

```nix
# 예: Vault IP 변경
vms = {
  vault = {
    ip = "10.0.10.20";  # 변경
    ...
  };
};
```

### 새 VM 추가

1. `homelab-constants.nix`의 `vms`에 정의 추가
2. `vms/` 디렉토리에 VM 설정 파일 생성
3. `modules/nixos/network.nix`에 TAP 인터페이스 추가

### VLAN 추가

1. `networks.vlans`에 새 VLAN 정의
2. `modules/nixos/network.nix`에 VLAN 인터페이스 설정 추가
3. 브릿지 VLAN 필터링 규칙 추가

## 설계 원칙

1. **Single Source of Truth**: 모든 하드코딩 값은 이 파일에만 존재
2. **순수 데이터**: 함수나 모듈 로직 없음 - 안전한 import 보장
3. **rec 사용**: 파일 내부에서 상호 참조 가능
4. **명시적 구조**: 네트워크, VM, 공통 설정이 명확히 분리됨
