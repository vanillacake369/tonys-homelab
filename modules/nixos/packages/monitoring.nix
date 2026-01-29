# 시스템 모니터링 패키지
# htop, btop 등 리소스 모니터링 도구
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    htop
    btop
    ncdu
    lsof
    psmisc # killall, pstree
  ];
}
