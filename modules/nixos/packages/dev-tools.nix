# 개발 도구 패키지
# git, strace 등 개발 관련 유틸리티
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    git
    strace
    moreutils
    expect
  ];
}
