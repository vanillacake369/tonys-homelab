# 네트워크 진단 및 유틸리티 패키지
# curl, wget, tcpdump 등 네트워크 도구
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    curl
    wget
    bind # dig, nslookup
    tcpdump
    nftables
  ];
}
