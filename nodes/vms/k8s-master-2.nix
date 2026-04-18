# Node: k8s-master-2
{...}: let
  network = import ../../network/topology.nix;
  net = network.vms.k8s-master-2; # ip, mac, tapId (topology.nix: 네트워크 할당)
in {
  imports = [
    ../interface.nix
    ../roles/k8s-master.nix
  ];

  node = {
    ip = net.ip;
    mac = net.mac;
    role = "k8s-master";
    hostType = "vm";
    parentHost = "homelab-1";
  };

  microvm = {
    hypervisor = "qemu";
    writableStoreOverlay = "/nix/.rw-store";
    vcpu = 4;
    mem = 4096;
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
    vsock.cid = 101;
  };

  # network-base (common.nix): useNetworkd, firewall 기본 설정 제공
  # k8s-master role: firewall.allowedTCPPorts [6443 2379 2380 10250 10251 10252] 추가
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
