{homelabConstants, ...}: let
  vmInfo = homelabConstants.vms.opnsense;
  bootFromIso = if vmInfo ? bootFromIso then vmInfo.bootFromIso else true;
in {
  # OPNsense는 FreeBSD 기반이므로 NixOS 구성을 내부에서 할 수 없습니다.
  # 따라서 이 모듈은 오직 VM의 "외형(Hardware)"만 정의합니다.

  microvm = {
    hypervisor = "qemu"; # FreeBSD 호환을 위해 반드시 qemu 사용
    vcpu = vmInfo.vcpu;
    mem = vmInfo.mem;

    # OPNsense는 두 개의 인터페이스가 필요합니다.
    interfaces = [
      {
        type = "bridge";
        id = vmInfo.wanTapId; # Host의 vmbr0에 연결될 포트
        mac = vmInfo.macWan;
        bridge = "vmbr0";
      }
      {
        type = "bridge";
        id = vmInfo.lanTapId; # Host의 vmbr1에 연결될 포트 (VLAN Trunk)
        mac = vmInfo.macLan;
        bridge = "vmbr0";
      }
    ];

    # QEMU의 풀 가상화 기능을 활용하여 ISO 및 디스크 로드
    qemu = {
      extraArgs = [
        # 1. 설치용 ISO 마운트 (초기 설치 시 필요)
        "-drive"
        "if=none,id=drive-iso,format=raw,file=${vmInfo.storage.iso}"
        "-device"
        "ide-cd,bus=ide.1,drive=drive-iso,id=cdrom"

        # 2. OPNsense가 설치될 메인 가상 디스크
        "-drive"
        "if=virtio,id=drive-main,file=${vmInfo.storage.image},format=raw"

        # 3. 부팅 순서 설정 (설치 시에는 'd', 설치 후에는 'c')
        "-boot"
        (if bootFromIso then "d" else "c")

        # 4. 성능을 위한 CPU 패스스루
        "-cpu"
        "host"

        # 5. VNC for GUI installer
        "-display"
        "none"
        "-vnc"
        ":1"
      ];
    };

    # MicroVM의 기본 공유 기능을 끄고 QEMU가 직접 제어하게 함
    shares = [];
  };

  # 가상 머신 관리를 위한 최소한의 NixOS 더미 설정
  # (VM이 실행되는 동안 호스트 시스템에서 식별하기 위함)
  networking.hostName = vmInfo.hostname;

  # 중요: OPNsense는 외부 이미지이므로 NixOS의 부트로더를 사용하지 않음
  system.stateVersion = homelabConstants.common.stateVersion;
}
