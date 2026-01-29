# 기본 시스템 유틸리티 패키지
# coreutils, findutils 등 필수 CLI 도구
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    coreutils
    findutils
    gnugrep
    gnused
  ];
}
