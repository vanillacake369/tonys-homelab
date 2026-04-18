# Node: k8s-worker-2
{...}: let
  network = import ../../network/topology.nix;
  net = network.vms.k8s-worker-2; # ip, mac, tapId (topology.nix: 네트워크 할당)
in {
  imports = [
    ../interface.nix
    ../roles/k8s-worker.nix
  ];

  node = {
    ip = net.ip;
    mac = net.mac;
    role = "k8s-worker";
    hostType = "vm";
    parentHost = "homelab-1";
  };

  microvm = {
    hypervisor = "qemu";
    writableStoreOverlay = "/nix/.rw-store";
    vcpu = 4;
    mem = 8192;
    interfaces = [{
      type = "tap";
      id = net.tapId;
      mac = net.mac;
    }];
    volumes = [{
      image = "kubelet.img";
      mountPoint = "/var/lib/kubelet";
      size = 2048;
    }];
    vsock.cid = 106;
  };

  # network-base (common.nix): useNetworkd, firewall 기본 설정 제공
  # k8s-worker role: firewall.allowedTCPPorts [10250] 추가
  systemd.network.networks."10-eth" = {
    matchConfig.MACAddress = net.mac;
    address = ["${net.ip}/24"];
    networkConfig = {
      Gateway = network.vlans.services.gateway;
      DNS = network.dns;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  system.stateVersion = "24.11";
}
