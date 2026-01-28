# VM 공통 설정 모듈
# 비-K8s VM들 (vault, jenkins, registry)에서 공유되는 설정
{
  lib,
  pkgs,
  data,
  ...
}: {
  # ============================================================
  # SSH 서비스 (hardened)
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # ============================================================
  # 시스템 유틸리티 패키지
  # ============================================================
  environment.systemPackages = with pkgs; [
    # 하드웨어 진단
    pciutils # lspci
    usbutils # lsusb
    dmidecode

    # GPU 진단
    mesa-demos # glxinfo, glxgears
    vulkan-tools # vulkaninfo

    # 네트워크 진단
    tcpdump
    nftables
    bind # dig, nslookup
    bridge-utils

    # 시스템 모니터링
    strace
    lsof
    psmisc # killall, pstree

    # 일반 유틸리티
    moreutils
    screen
  ];
}
