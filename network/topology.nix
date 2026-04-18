# 네트워크 토폴로지 상수
# - 이 homelab 의 물리/가상 네트워크 구조 선언
# - 여러 노드가 공유하는 WAN, VLAN, K8s, Tailscale 상수
# - 노드별 데이터(IP, MAC)는 각 nodes/*.nix 에 인라인 선언
#
# 참조처:
#   nodes/physical/homelab-1.nix  → ../../network/topology.nix
#   nodes/vms/*.nix               → ../../network/topology.nix
#   ansible/inventory.nix         → ../network/topology.nix
{
  # WAN (물리 호스트 외부 네트워크)
  wan = {
    host = "192.168.45.82";
    gateway = "192.168.45.1";
    prefixLength = 24;
  };

  dns = ["8.8.8.8" "1.1.1.1"];

  # VLAN 구성
  vlans = {
    # VLAN 10: 관리 네트워크 (호스트 관리용)
    management = {
      id = 10;
      network = "10.0.10.0/24";
      gateway = "10.0.10.1";
      host = "10.0.10.5";
      prefixLength = 24;
    };
    # VLAN 20: 서비스 네트워크 (Kubernetes 클러스터)
    services = {
      id = 20;
      network = "10.0.20.0/24";
      gateway = "10.0.20.1";
      host = "10.0.20.5";
      prefixLength = 24;
    };
  };

  # Tailscale 오버레이 네트워크 (CGNAT 대역)
  tailscale = {
    network = "100.64.0.0/10";
    host = "100.70.221.61";
  };

  # Kubernetes 클러스터 네트워킹
  kubernetes = {
    pod_cidr = "10.244.0.0/16";
    service_cidr = "10.96.0.0/12";
    api_vip = "10.0.20.100"; # HA VIP Endpoint
    cilium_helm_version = "1.15.5";
  };

  # 물리 호스트 메타데이터 (justfile/ansible 등 외부 도구의 노드 해석용)
  # - ip: SSH 접근 IP (WAN)
  # - user: SSH 사용자 (node.user 와 동기화)
  hosts = {
    homelab-1 = {ip = "192.168.45.82"; user = "limjihoon";};
  };

  # VM 네트워크 할당 (CIDR 충돌 방지: services VLAN 10.0.20.0/24 내 순차 할당)
  # - ip, mac, tapId: 네트워크 디바이스 할당 → 이 파일에서 중앙 관리
  # - vcpu, mem, vsockCid: 컴퓨트 리소스 → 각 nodes/vms/*.nix 에 인라인
  # VM 추가/제거 시 이 파일만 수정하면 homelab-1.nix TAP 설정과 ansible 인벤토리에 자동 반영
  vms = {
    k8s-master-1 = {ip = "10.0.20.10"; mac = "02:00:00:00:20:10"; tapId = "vm-k8s-m1";};
    k8s-master-2 = {ip = "10.0.20.11"; mac = "02:00:00:00:20:11"; tapId = "vm-k8s-m2";};
    k8s-master-3 = {ip = "10.0.20.12"; mac = "02:00:00:00:20:12"; tapId = "vm-k8s-m3";};
    k8s-worker-1 = {ip = "10.0.20.21"; mac = "02:00:00:00:20:21"; tapId = "vm-k8s-w1";};
    k8s-worker-2 = {ip = "10.0.20.22"; mac = "02:00:00:00:20:22"; tapId = "vm-k8s-w2";};
    k8s-worker-3 = {ip = "10.0.20.23"; mac = "02:00:00:00:20:23"; tapId = "vm-k8s-w3";};
  };
}
