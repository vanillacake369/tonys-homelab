# Kubernetes Master Profile
{
  pkgs,
  data,
  microvmTarget,
  ...
}: let
  vmInfo = data.vms.definitions.${microvmTarget};
in {
  # Master 전용 패키지
  environment.systemPackages = with pkgs; [
    etcd
  ];

  # KUBECONFIG 환경변수 (kubeadm init 후 사용)
  environment.variables.KUBECONFIG = "/etc/kubernetes/admin.conf";

  # Master 전용 방화벽 설정
  networking.firewall.allowedTCPPorts = [
    vmInfo.ports.api # 6443 - API server
    vmInfo.ports.etcdClient # 2379 - etcd client
    vmInfo.ports.etcdPeer # 2380 - etcd peer
    vmInfo.ports.scheduler # 10251 - scheduler
    vmInfo.ports.controller # 10252 - controller-manager
    10257 # controller-manager secure
    10259 # scheduler secure
  ];

  networking.firewall.allowedUDPPorts = [
    8472 # Flannel/Cilium VXLAN
  ];
}
