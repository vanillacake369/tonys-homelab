# Homelab 개선 ToDo List

> 분석 일자: 2026-01-26
> 기준: 코드베이스 전체 분석 결과

---

## 📌 Phase 1: 보안 (Security) - ✅ 완료

### 🔴 CRITICAL

- [x] **P1-1: VM 빈 비밀번호 제거** ✅
  - 해결: `mk-microvms.nix`에서 `hashedPasswordFile`로 sops 시크릿 사용
  - 변경 파일: `lib/mk-microvms.nix`, 모든 VM 파일

### 🟠 HIGH

- [x] **P1-2: SSH 키 하드코딩 제거** ✅
  - 해결: `mkVmCommonModule`에서 `specialArgs.sshPublicKey` 사용
  - 변경 파일: 모든 VM 파일에서 하드코딩된 SSH 키 제거

- [x] **P1-3: SSH 설정 강화** ✅
  - 해결: 모든 VM에서 다음 설정 적용
    - `PermitRootLogin = "prohibit-password"`
    - `PasswordAuthentication = false`
  - 변경 파일: 모든 VM 파일

- [x] **P1-4: Tailscale 인증 키 형식 수정** ✅
  - 해결: OAuth client secret을 직접 auth key로 사용
  - 변경 파일: `modules/nixos/tailscale.nix`, `modules/nixos/sops.nix`

---

## 📌 Phase 2: 코드 품질 (Code Quality) - ✅ 완료

### 🔴 CRITICAL

- [x] **P2-1: K8s 커널 모듈 공통화** ✅
  - 해결: `modules/nixos/k8s-base.nix` 생성
  - 포함 내용: 커널 모듈, sysctl, k8s-kernel-modules 서비스, hosts, SSH, containerd

- [x] **P2-2: VM 기본 모듈 생성** ✅
  - 해결: `modules/nixos/vm-base.nix` 생성
  - 포함 내용: SSH hardened 설정

### 🟠 HIGH

- [x] **P2-3: 네트워크 설정 중복 제거** ✅
  - 해결: 각 VM에서 `vm-base.nix` import, 네트워크 설정은 VM별 유지 (VLAN 다름)

- [x] **P2-4: SSH 설정 중복 제거** ✅
  - 해결: `k8s-base.nix`와 `vm-base.nix`에서 공통 SSH 설정 관리

- [x] **P2-5: hosts 파일 엔트리 중복 제거** ✅
  - 해결: `k8s-base.nix`에서 K8s 노드 hosts 엔트리 중앙 관리

---

## 📌 Phase 3: 설정 일관성 (Configuration Consistency) - ✅ 완료

### 🟠 HIGH

- [x] **P3-1: 네트워크 설정 방식 통일** ✅
  - 해결: 모든 VM을 `systemd.network.networks` 방식으로 통일
  - 호스트와 동일한 systemd-networkd 기반 설정

- [x] **P3-2: 방화벽 포트 설정 정리** ✅
  - 해결: `k8s-base.nix`에 kubelet API 포트(10250) 추가
  - Flannel VXLAN(8472), kubelet 통신을 위한 공통 방화벽 규칙

### 🟡 MEDIUM

- [x] **P3-3: sops.nix 중복 정의 제거** ✅
  - Phase 1에서 해결됨

- [x] **P3-4: stateVersion 중앙 집중화** ✅
  - 모든 VM이 `homelabConstants.common.stateVersion` 사용 중

---

## 📌 Phase 4: 자동화 및 동적 생성 - ✅ 완료

### 🟡 MEDIUM

- [x] **P4-1: TAP 인터페이스 자동 생성** ✅
  - 해결: `lib.mapAttrs'`로 `homelabConstants.vms`에서 동적 생성
  - 216줄 → 150줄로 감소

- [x] **P4-2: Colmena VM 필터링 구현** ✅
  - 해결: 현재 로직 유지 (`deployment.colmena or true`)
  - 주석 추가로 의도 명확화

---

## 📌 Phase 5: 미완성 구현 완료 - ✅ 완료

### 🟠 HIGH

- [x] **P5-1: K8s 자동 조인 구현** ✅
  - 해결: NixOS kubernetes 모듈의 `easyCerts` 활용
  - 불필요한 `k8s-auto-join` systemd 서비스 제거
  - `services.kubernetes.kubelet.kubeconfig.server` 설정으로 대체

- [x] **P5-2: K8s 클러스터 설정 보완** ✅
  - 해결: Colmena VM 배포 시 sops.nix 제거 (VM은 virtiofs로 시크릿 수신)
  - `mk-colmena.nix`에서 불필요한 sops 모듈 import 제거

### 🟡 MEDIUM

- [x] **P5-3: Tailscale 자동 연결 에러 핸들링** ✅
  - 해결: 에러 로깅, 재시도 제한 (5회/300초), 데몬 대기 로직 추가

---

## 📌 Phase 6: 코드 정리 (Cleanup) - ✅ 완료

### 🟡 MEDIUM

- [x] **P6-1: 미사용 모듈 정리** ✅
  - 삭제: `modules/virtualization.nix` (MicroVM 사용으로 불필요)
  - 삭제: `lib/mk-vm-network.nix` (미사용)

- [x] **P6-2: GPU 설정** ✅
  - 유지: 주석은 향후 활성화를 위한 문서로 유지

- [x] **P6-3: TODO 주석 정리** ✅
  - Phase 1-2에서 관련 코드가 이미 리팩토링됨
  - 해결 후 TODO 주석 제거

- [x] **P6-4: "TEMPORARY" 주석 표시된 설정 검토** ✅
  - 해결: Phase 1에서 이미 모든 임시 설정 제거됨
  - SSH 설정 `prohibit-password`로 강화 완료
  - README 문서 업데이트

---

## 📌 Phase 7: 빌드/배포 개선 - ✅ 완료

### 🟡 MEDIUM

- [x] **P7-1: CI/로컬 빌드 일관성** ✅
  - 해결: `homelabCi` 구성 제거, 환경변수 `MICROVM_TARGETS` 기반으로 통합
  - CI에서 `MICROVM_TARGETS=none` 사용
  - 변경 파일: `flake.nix`, `.github/workflows/ci-common.yml`

- [x] **P7-2: LVM thin pool 문서화** ✅
  - 해결: `disko-config.nix` 상단에 오버커밋 전략 및 모니터링 가이드 추가
  - 포함 내용: 오버커밋 근거, 모니터링 명령어, 알림 임계값

---

## 📌 Phase 8: 문서화 (Documentation) - ✅ 완료

### 🟡 MEDIUM

- [x] **P8-1: homelabConstants 스키마 문서화** ✅
  - 해결: `lib/README.md`에 VM 스키마 ER 다이어그램 추가
  - Mermaid erDiagram으로 필수/선택 필드 시각화

- [x] **P8-2: 네트워크 토폴로지 문서화** ✅
  - 해결: `modules/README.md`에 네트워크 아키텍처 다이어그램 추가
  - 트래픽 흐름 시퀀스 다이어그램 포함

- [x] **P8-3: 배포 워크플로우 문서화** ✅
  - 해결: `README.md`에 배포 플로우 다이어그램 추가
  - Local → CI → Remote 흐름 시각화

### 🔵 LOW

- [x] **P8-4: lib/ 함수 문서화** ✅
  - 해결: `lib/README.md`에 모듈 의존성 플로우차트 추가
  - flake.nix → lib/ → outputs 관계 시각화

---

## 📊 우선순위 요약

| Phase | 우선순위 | 항목 수 | 예상 영향도 |
|-------|----------|---------|-------------|
| Phase 1 | 🔴 즉시 | 4 | 보안 취약점 해결 |
| Phase 2 | 🟠 높음 | 5 | 코드 중복 60% 감소 |
| Phase 3 | 🟠 높음 | 4 | 설정 일관성 확보 |
| Phase 4 | 🟡 중간 | 2 | 유지보수성 향상 |
| Phase 5 | 🟠 높음 | 3 | 기능 완성도 |
| Phase 6 | 🟡 중간 | 4 | 기술 부채 해소 |
| Phase 7 | 🟡 중간 | 4 | 온보딩/유지보수 |
| Phase 8 | 🟡 중간 | 2 | 빌드 안정성 |

---

## 🏷️ 라벨 정의

- 🔴 **CRITICAL**: 즉시 해결 필요 (보안, 기능 장애)
- 🟠 **HIGH**: 빠른 시일 내 해결 (주요 기술 부채)
- 🟡 **MEDIUM**: 계획적 해결 (개선 사항)
- 🔵 **LOW**: 시간 여유 시 해결 (nice-to-have)
