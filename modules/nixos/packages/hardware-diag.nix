# 하드웨어 진단 패키지
# lspci, lsusb 등 하드웨어 정보 도구
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    pciutils # lspci
    usbutils # lsusb
    dmidecode
  ];
}
