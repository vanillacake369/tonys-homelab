# ============================================================
# Ansible Dynamic Inventory Bridge (Nix -> JSON)
# ============================================================
# - VM 목록/IP: network/topology.nix vms 섹션 (CIDR 단일 관리)
# - 네트워크 상수: network/topology.nix
# - role: VM 이름 패턴에서 동적 도출 (k8s-master-* / k8s-worker-*)
# - vlan: IP 프리픽스를 topology.nix의 VLAN network와 매칭하여 도출
# ------------------------------------------------------------
{...}: let
  network = import ../network/topology.nix;

  # VM 이름에서 Ansible role 도출 (k8s-master-* → "master")
  roleOf = name:
    if builtins.match "k8s-master-.*" name != null
    then "master"
    else if builtins.match "k8s-worker-.*" name != null
    then "worker"
    else "unknown";

  # IP 프리픽스(/24)를 topology.nix VLAN network와 대조해 VLAN 이름 도출
  # VLAN 구성이 바뀌어도 topology.nix 수정만으로 자동 반영됨
  vlanOf = ip: let
    prefix3 = addr: let
      m = builtins.match "([0-9]+\\.[0-9]+\\.[0-9]+)\\.[0-9]+(/[0-9]+)?" addr;
    in
      if m != null
      then builtins.head m
      else "";
    ipPfx = prefix3 ip;
    matches =
      builtins.filter
      (v: prefix3 network.vlans.${v}.network == ipPfx)
      (builtins.attrNames network.vlans);
  in
    if matches != []
    then builtins.head matches
    else "unknown";

  # VM 이름 목록: topology.nix vms 키 → 사전순 정렬
  allVmNames = builtins.attrNames network.vms;
  masterHosts = builtins.filter (n: roleOf n == "master") allVmNames;
  workerHosts = builtins.filter (n: roleOf n == "worker") allVmNames;
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
    node_vlan = vlanOf vm.ip;
    node_role = roleOf name;
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
      cilium_helm_version = network.kubernetes.cilium_helm_version;
    };
  };

  k8s_masters = mkGroup masterHosts;
  k8s_workers = mkGroup workerHosts;
}
