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

- [ ] **P3-2: 방화벽 포트 설정 정리** (별도 이슈)
  - K8s 클러스터 조인 문제와 연관 - 추가 조사 필요

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

## 📌 Phase 5: 미완성 구현 완료 - 부분 완료

### 🟠 HIGH (별도 이슈)

- [ ] **P5-1: K8s 자동 조인 구현** (별도 이슈로 관리)
- [ ] **P5-2: K8s 클러스터 설정 보완** (별도 이슈로 관리)

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

- [ ] **P6-4: "TEMPORARY" 주석 표시된 설정 검토**
  - 영향 파일: 모든 VM 파일
  - 현재: 개발용 임시 설정이 "TEMPORARY" 주석과 함께 존재
  - 해결: 프로덕션 전환 시 모두 제거/수정

---

## 📌 Phase 7: 문서화 (Documentation)

### 🟡 MEDIUM

- [ ] **P7-1: homelabConstants 스키마 문서화**
  - 현재: `homelabConstants.vms` 구조가 문서화되지 않음
  - 필요 내용:
    - 필수 필드
    - 선택 필드 및 기본값
    - `deployment.tags`, `vlan` 등 유효 값

- [ ] **P7-2: 네트워크 토폴로지 문서화**
  - 영향 파일: `modules/nixos/network.nix`
  - 필요 내용:
    - VLAN ID 선택 이유
    - 트래픽 흐름 설명
    - 트러블슈팅 가이드

- [ ] **P7-3: 배포 워크플로우 문서화**
  - 필요 내용:
    - 단일 VM vs 전체 VM 배포 방법
    - 롤백 절차
    - Colmena 태그 사용법 (`k8s`, `vm-vault` 등)

### 🔵 LOW

- [ ] **P7-4: lib/ 함수 문서화**
  - 영향 파일:
    - `lib/mk-microvms.nix` - vmSecrets 매핑 설명
    - `lib/mk-special-args.nix` - SSH_PUB_KEY 환경변수 요구사항
    - `lib/mk-colmena.nix` - 메타데이터 구조

---

## 📌 Phase 8: 빌드/배포 개선

### 🟡 MEDIUM

- [ ] **P8-1: CI/로컬 빌드 일관성**
  - 영향 파일: `flake.nix:111-116`
  - 현재: `nixosConfigurations.homelabCi`가 `microvmTargets = []`로 VM 빌드 스킵
  - 해결: 모듈 옵션 기반으로 전환 또는 명확한 네이밍/문서화

- [ ] **P8-2: LVM thin pool 문서화**
  - 영향 파일: `disko-config.nix:60-132`
  - 현재: 2.1x 오버커밋 (논리 800G / 물리 380G)
  - 해결: 근거 및 모니터링 전략 문서화

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
