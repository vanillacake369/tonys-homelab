# ADR 0005: 스토리지 전략

## 상태

채택.

## 맥락

현재 클러스터는 단일 물리 호스트 위의 VM들로 구성된다. 물리 디스크 장애 또는 물리 호스트 장애는
모든 VM에 영향을 준다. 따라서 분산 스토리지를 올려도 물리 failure domain 은 분산되지 않는다.

현재 구현은 local-path-provisioner를 기본 StorageClass로 사용한다.

## 옵션

| 옵션 | 설명 | 장점 | 단점 |
| --- | --- | --- | --- |
| hostPath 직접 사용 | Pod가 노드 경로를 직접 mount | 개념 학습 쉬움 | PVC lifecycle, scheduling 통합 약함 |
| local-path-provisioner | 노드 로컬 경로를 동적 PV로 제공 | 단순, 홈랩 학습에 적합 | 노드 장애 시 데이터 이동 불가 |
| Longhorn | 복제 기반 block storage | 홈랩 HA storage 학습에 적합 | 단일 물리 호스트에서는 복제 효과 제한 |
| Rook Ceph | Ceph를 Kubernetes operator로 운영 | Ceph/RBD/CephFS 학습 가능 | 메모리/디스크/운영 복잡도 높음 |
| 외부 NAS/NFS | NAS를 PV backend로 사용 | 클러스터와 데이터 분리 | NAS가 별도 SPOF, 성능/권한 이슈 |

## 결정

현재는 `local-path-provisioner`를 유지한다. Ceph는 보류한다.

## 근거

- 단일 물리 호스트에서는 Ceph/Longhorn 복제가 물리 장애를 해결하지 못한다.
- local-path는 PVC, StorageClass, volumeBindingMode, reclaimPolicy 학습에 충분하다.
- 현재 앱 규모에서는 storage operator 운영보다 백업/복구 절차를 먼저 익히는 것이 우선이다.
- `WaitForFirstConsumer`는 Pod scheduling 이후 PV를 노드에 묶어, local storage의 위치 제약을 드러낸다.
- `Retain`은 백업 자동화 전 단계에서 PVC 삭제로 인한 데이터 손실을 줄인다.

## 운영 명세

- 기본 StorageClass는 `local-path`다.
- provisioner 데이터 경로는 `/opt/local-path-provisioner`다.
- stateful 앱은 nodeSelector 또는 affinity로 데이터 노드 배치를 명시한다.
- 중요한 데이터는 PV 존재만 믿지 않고 별도 backup/restore runbook을 가진다.
- local-path는 HA storage가 아니며, 문서와 앱 README에 이 제한을 명시한다.

## 확장 전략

| 상황 | 선택 |
| --- | --- |
| 학습/개인 앱 | local-path 유지 |
| 데이터가 중요해짐 | restic/VolSync/NAS 백업 ADR 작성 |
| 물리 호스트 2대 이상 | Longhorn PoC |
| 물리 호스트 3대 이상 + 전용 디스크 | Rook Ceph PoC |
| RWX 공유 볼륨 필요 | NFS 또는 CephFS 검토 |

## 재검토 조건

- stateful 앱이 2개 이상이고 수동 복구가 부담된다.
- 물리 호스트가 2대 이상으로 늘어난다.
- Ceph 자체 학습이 명시 목표가 된다.
- 백업/복구 RTO/RPO를 수치로 정의해야 하는 서비스가 생긴다.

## 근거 자료

- 로컬: `deploy/k8s/infrastructure/storage/deployment.yaml`, `storageclass.yaml`, `network/topology.nix`
- local-path-provisioner: https://github.com/rancher/local-path-provisioner
- Kubernetes StorageClass: https://kubernetes.io/docs/concepts/storage/storage-classes/
- Longhorn: https://longhorn.io/docs/latest/what-is-longhorn/
- Rook Ceph: https://rook.io/docs/rook/latest-release/Getting-Started/intro/
