# 터미널 멀티플렉서 패키지
# zellij, screen 등
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    zellij
    screen
  ];
}
