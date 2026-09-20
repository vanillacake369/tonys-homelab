# ============================================================
# Ansible Dynamic Inventory Bridge (Nix -> JSON)
# ============================================================
# - K8s node 목록/IP: network/topology.nix hosts/vms 의 shallow role facts
# - 네트워크 상수: network/topology.nix
# - role/cluster/network: topology.nix node contract에서 직접 참조
# ------------------------------------------------------------
{...}: let
  network = import ../network/topology.nix;

  ansibleRoleOf = role:
    if role == "k8s-master"
    then "master"
    else if role == "k8s-worker"
    then "worker"
    else "unknown";

  isK8sNode = node:
    node ? role
    && node
    ? cluster
    && node.cluster == network.kubernetes.cluster
    && (ansibleRoleOf node.role) != "unknown";

  allVmNames = builtins.attrNames network.vms;
  allHostNames = builtins.attrNames network.hosts;
  clusterVmNames = builtins.filter (n: isK8sNode network.vms.${n}) allVmNames;
  clusterPhysicalNames = builtins.filter (n: isK8sNode network.hosts.${n}) allHostNames;
  clusterNodeNames = clusterVmNames ++ clusterPhysicalNames;
  nodeRole = name:
    if builtins.hasAttr name network.vms
    then network.vms.${name}.role
    else network.hosts.${name}.role;
  masterHosts = builtins.filter (n: ansibleRoleOf (nodeRole n) == "master") clusterNodeNames;
  workerHosts = builtins.filter (n: ansibleRoleOf (nodeRole n) == "worker") clusterNodeNames;
  allNodes = masterHosts ++ workerHosts;

  # [1] 데이터 변환기: topology.nix node facts 를 Ansible 호스트 변수로 매핑
  # SSH 연결 설정은 justfile의 ANSIBLE_SSH_ARGS="-F .cache/ssh-config"에 위임
  # ------------------------------------------------------------
  toVmAnsibleHost = name: let
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
  toPhysicalAnsibleHost = name: let
    host = network.hosts.${name};
  in {
    ansible_user = host.user;
    ansible_python_interpreter = "/run/current-system/sw/bin/python3";
    node_name = name;
    node_hostname = name;
    node_cluster = host.cluster;
    node_uplink_ip = host.uplink.ip;
    node_vlan = host.network or "uplink";
    node_role = ansibleRoleOf host.role;
  };
  toAnsibleHost = name:
    if builtins.hasAttr name network.vms
    then toVmAnsibleHost name
    else toPhysicalAnsibleHost name;

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
