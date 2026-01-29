# 기타 유틸리티 패키지
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    neofetch
    ngrok
  ];
}
