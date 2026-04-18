# Atom: Network Base
# 모든 homelab 노드(물리/VM)에 적용되는 네트워크 기반 설정
# - systemd-networkd 활성화 (NetworkManager 비활성)
# - 기본 방화벽 활성화 + SSH 포트 허용
# - 역할별 추가 포트는 각 role 파일에서 선언 (listOf 자동 병합)
{...}: {
  networking.networkmanager.enable = false;
  networking.useDHCP = false;
  networking.useNetworkd = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22];
  };
}
