# 네트워크 토폴로지 상수
# - 이 homelab 의 물리/가상 네트워크 구조 선언
# - 여러 노드가 공유하는 WAN, VLAN, K8s, Tailscale 상수
{
  # WAN (물리 호스트 외부 네트워크)
  wan = {
    host = "192.168.45.82";
    gateway = "192.168.45.1";
    prefixLength = 24;
  };

  dns = ["8.8.8.8" "1.1.1.1"];

  # VLAN 정의 (Layer 2 — 전체 네트워크 공유)
  # 호스트별 IP 할당은 hosts.*.vlans 에서 선언
  vlans = {
    management = {
      id = 10;
      network = "10.0.10.0/24";
      prefixLength = 24;
    };
    services = {
      id = 20;
      network = "10.0.20.0/24";
      prefixLength = 24;
    };
  };

  # Tailscale 오버레이 네트워크 (CGNAT 대역)
  # host IP는 동적 할당 — justfile에서 tailscale status로 런타임 파싱
  tailscale = {
    network = "100.64.0.0/10";
  };

  # Kubernetes 클러스터 네트워킹
  kubernetes = {
    pod_cidr = "10.244.0.0/16";
    service_cidr = "10.96.0.0/12";
    api_vip = "10.0.20.100";
    cilium_helm_version = "1.15.5";
  };

  # 물리 호스트 메타데이터
  # - ip: SSH 접근 IP (WAN)
  # - user: SSH 사용자
  # - vlans: 호스트별 VLAN IP 할당 (gateway = 이 호스트의 VLAN 게이트웨이 IP)
  hosts = {
    homelab-1 = {
      ip = "192.168.45.82";
      user = "limjihoon";
      vlans = {
        management = {gateway = "10.0.10.1";};
        services = {gateway = "10.0.20.1";};
      };
    };
  };

  # VM 레지스트리: 네트워크 할당 + 컴퓨트 리소스
  vms = {
    k8s-master-1 = {
      ip = "10.0.20.10";
      mac = "02:00:00:00:20:10";
      tapId = "vm-k8s-m1";
      vcpu = 4;
      mem = 4096;
      diskSize = 40;
    };
    k8s-master-2 = {
      ip = "10.0.20.11";
      mac = "02:00:00:00:20:11";
      tapId = "vm-k8s-m2";
      vcpu = 4;
      mem = 4096;
      diskSize = 40;
    };
    k8s-master-3 = {
      ip = "10.0.20.12";
      mac = "02:00:00:00:20:12";
      tapId = "vm-k8s-m3";
      vcpu = 4;
      mem = 4096;
      diskSize = 40;
    };
    k8s-worker-1 = {
      ip = "10.0.20.21";
      mac = "02:00:00:00:20:21";
      tapId = "vm-k8s-w1";
      vcpu = 8;
      mem = 16384;
      diskSize = 60;
    };
    k8s-worker-2 = {
      ip = "10.0.20.22";
      mac = "02:00:00:00:20:22";
      tapId = "vm-k8s-w2";
      vcpu = 4;
      mem = 8192;
      diskSize = 40;
    };
    k8s-worker-3 = {
      ip = "10.0.20.23";
      mac = "02:00:00:00:20:23";
      tapId = "vm-k8s-w3";
      vcpu = 4;
      mem = 8192;
      diskSize = 40;
    };
  };
}
