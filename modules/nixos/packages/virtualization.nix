# 가상화 관련 패키지
# bridge-utils 등 네트워크 가상화 도구
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    bridge-utils
  ];
}
