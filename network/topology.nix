# Shallow desired-fact log for this homelab.
# Put facts here only when multiple consumers need the same source of truth.
# Do not put derived names, module-local conventions, or full service config here.
rec {
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
    cluster = "homelab";
    version = "1.35.3";
    pod_cidr = "10.244.0.0/16";
    service_cidr = "10.96.0.0/12";
    api_vip = "10.0.20.100";
    cilium_helm_version = "1.19.1";
    lb_pool = "10.0.20.240/29";
  };

  storage = {
    localPath = {
      dataNodes = ["k8s-worker-1"];
      nodeSelector = {
        "homelab.tonys.dev/storage" = "local-path";
      };
    };
  };

  # 물리 호스트 메타데이터
  # - role: 이 host 의 active fleet role
  # - cluster: Kubernetes role 일 때 소속 cluster
  # - user: SSH 사용자
  # - uplink: physical upstream interface/network facts
  # - vlans: 호스트별 VLAN interface address
  hosts = {
    homelab-1 = {
      role = "host";
      user = "limjihoon";
      uplink = {
        interface = "enp1s0";
        ip = "192.168.45.82";
        prefixLength = 24;
        gateway = "192.168.45.1";
      };
      vlans = {
        management = {address = "10.0.10.1";};
        services = {address = "10.0.20.1";};
      };
    };
    homelab-2 = {
      role = "k8s-worker";
      cluster = "homelab";
      user = "limjihoon";
      uplink = {
        interface = "wlp2s0";
        ip = "192.168.45.83";
        prefixLength = 24;
        gateway = "192.168.45.1";
      };
    };
  };

  # VM 레지스트리: 네트워크 할당 + 컴퓨트 리소스
  vms = {
    k8s-master-1 = {
      role = "k8s-master";
      cluster = "homelab";
      network = "services";
      parentHost = "homelab-1";
      ip = "10.0.20.10";
      mac = "02:00:00:00:20:10";
      tapId = "vm-k8s-m1";
      vcpu = 2;
      mem = 4096;
      diskSize = 20;
    };
    k8s-worker-1 = {
      role = "k8s-worker";
      cluster = "homelab";
      network = "services";
      parentHost = "homelab-1";
      ip = "10.0.20.21";
      mac = "02:00:00:00:20:21";
      tapId = "vm-k8s-w1";
      vcpu = 6;
      mem = 8192;
      diskSize = 40;
    };
    k8s-worker-2 = {
      role = "k8s-worker";
      cluster = "homelab";
      network = "services";
      parentHost = "homelab-1";
      ip = "10.0.20.22";
      mac = "02:00:00:00:20:22";
      tapId = "vm-k8s-w2";
      vcpu = 4;
      mem = 8192;
      diskSize = 40;
    };
  };
}
