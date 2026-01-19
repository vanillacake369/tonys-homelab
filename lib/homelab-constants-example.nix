# Homelab Infrastructure Constants (EXAMPLE)
# 이 파일은 Public에 공개해도 안전한 가상의 값들로 채워져 있습니다.
rec {
  # Network topology
  networks = {
    wan = {
      network = "10.99.99.0/24"; # 마스킹됨
      host = "10.99.99.100"; # 마스킹됨
      gateway = "10.99.99.1"; # 마스킹됨
      prefixLength = 24;
    };

    dns = ["1.1.1.1" "8.8.8.8"];

    vlans = {
      management = {
        id = 10;
        network = "172.16.10.0/24"; # 마스킹됨
        gateway = "172.16.10.1";
        host = "172.16.10.5";
        prefixLength = 24;
      };
      services = {
        id = 20;
        network = "172.16.20.0/24"; # 마스킹됨
        gateway = "172.16.20.1";
        host = "172.16.20.5";
        prefixLength = 24;
      };
    };
  };

  # VM inventory
  vms = {
    vault = {
      vlan = "management";
      ip = "172.16.10.11";
      mac = "02:00:00:AA:BB:CC"; # 가짜 MAC
      vsockCid = 100;
      vcpu = 2;
      mem = 2047;
      tapId = "vm-vault";
      hostname = "vault";
      ports = {
        ssh = 22;
        api = 8200;
      };
      storage = {
        source = "/var/lib/microvms/vault/data";
        mountPoint = "/var/lib/vault";
        tag = "vault-storage";
      };
    };
    # ... 다른 VM들도 동일하게 가짜 IP/MAC으로 작성 ...
  };

  common = {
    stateVersion = "24.11";
    hypervisor = "qemu";
  };

  host = {
    username = "example-user"; # 마스킹됨
    hostname = "example-lab"; # 마스킹됨
    deployment = {
      targetHost = "example-lab";
      targetUser = "example-user";
    };
  };
}
