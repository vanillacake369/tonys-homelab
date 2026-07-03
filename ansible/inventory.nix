# ============================================================
# Ansible Dynamic Inventory Bridge (Nix -> JSON)
# ============================================================
# - VM 목록/IP: network/topology.nix vms 섹션 (CIDR 단일 관리)
# - 네트워크 상수: network/topology.nix
# - role/cluster/network: topology.nix VM contract에서 직접 참조
# ------------------------------------------------------------
{...}: let
  network = import ../network/topology.nix;

  ansibleRoleOf = role:
    if role == "k8s-master"
    then "master"
    else if role == "k8s-worker"
    then "worker"
    else "unknown";

  # VM 이름 목록: topology.nix vms 키 → 사전순 정렬
  allVmNames = builtins.attrNames network.vms;
  clusterVmNames = builtins.filter (n: network.vms.${n}.cluster == network.kubernetes.cluster) allVmNames;
  masterHosts = builtins.filter (n: ansibleRoleOf network.vms.${n}.role == "master") clusterVmNames;
  workerHosts = builtins.filter (n: ansibleRoleOf network.vms.${n}.role == "worker") clusterVmNames;
  allNodes = masterHosts ++ workerHosts;

  # [1] 데이터 변환기: topology.nix VM 네트워크 할당을 Ansible 호스트 변수로 매핑
  # SSH 연결 설정은 justfile의 ANSIBLE_SSH_ARGS="-F .cache/ssh-config"에 위임
  # ------------------------------------------------------------
  toAnsibleHost = name: let
    vm = network.vms.${name};
  in {
    ansible_host = vm.ip;
    ansible_user = "root";
    ansible_python_interpreter = "/run/current-system/sw/bin/python3";
    node_name = name;
    node_hostname = name;
    node_cluster = vm.cluster;
    node_vlan = vm.network;
    node_role = ansibleRoleOf vm.role;
  };

  # [2] 그룹 생성기
  # ------------------------------------------------------------
  mkGroup = hosts: {
    inherit hosts;
    vars = {};
  };
in {
  # 모든 호스트의 상세 변수 정의
  _meta.hostvars = builtins.listToAttrs (map (name: {
      inherit name;
      value = toAnsibleHost name;
    })
    allNodes);

  # 글로벌 변수 (network/topology.nix 에서 직접 참조)
  all = {
    children = ["k8s_masters" "k8s_workers"];
    vars = {
      pod_cidr = network.kubernetes.pod_cidr;
      service_cidr = network.kubernetes.service_cidr;
      api_vip = network.kubernetes.api_vip;
      k8s_version = network.kubernetes.version;
      cilium_helm_version = network.kubernetes.cilium_helm_version;
    };
  };

  k8s_masters = mkGroup masterHosts;
  k8s_workers = mkGroup workerHosts;
}
