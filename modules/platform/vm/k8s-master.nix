# Kubernetes Master Profile (Infrastructure only)
{ pkgs, data, microvmTarget, ... }: 
let
  vmInfo = data.vms.definitions.${microvmTarget};
in {
  # Master 전용 패키지 (etcd 바이너리 등)
  environment.systemPackages = with pkgs; [ etcd ];

  # KUBECONFIG 환경변수
  environment.variables.KUBECONFIG = "/etc/kubernetes/admin.conf";

  # 방화벽 해제 (K8s 노드 간 자유로운 통신 보장)
  networking.firewall.enable = false;
}
