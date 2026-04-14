# ============================================================
# Ansible Dynamic Inventory Bridge (Nix -> JSON)
# ============================================================
# 이 파일은 data/ 디렉토리의 모든 순수 데이터를 Ansible의 인벤토리 규격으로 변환합니다.
# ------------------------------------------------------------
{
  data,
  deploy_target ? "",
}: let
  vms = data.vms;
  network = data.network;
  host = data.hosts.definitions.${data.hosts.default};
  inherit (vms) definitions k8s;

  # SSOT: Use dynamically detected deploy_target if available, fallback to data layer
  jumpHost =
    if deploy_target != ""
    then deploy_target
    else host.deployment.targetHost;
  jumpUser = host.deployment.targetUser;

  # Identity file logic
  idFile = builtins.getEnv "SSH_KEY_FILE";
  idArg =
    if idFile != ""
    then "-o IdentityFile=${idFile}"
    else "";

  proxySshArgs = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null ${idArg} -o ProxyJump=${jumpUser}@${jumpHost}";

  # [1] 데이터 변환기: Nix VM 정의를 Ansible 호스트 변수로 매핑
  # ------------------------------------------------------------
  toAnsibleHost = name: let
    vm = definitions.${name};
  in {
    # Ansible 필수 변수
    ansible_host = vm.ip;
    ansible_user = vm.deployment.user or "root";

    # NixOS 최적화: Python 인터프리터 경로 명시
    ansible_python_interpreter = "/run/current-system/sw/bin/python3";
    ansible_ssh_common_args = proxySshArgs;

    # 플레이북에서 활용할 커스텀 메타데이터
    node_name = name;
    node_hostname = vm.hostname;
    node_vlan = vm.vlan;
    node_role =
      if builtins.elem name k8s.masters
      then "master"
      else "worker";
  };

  # [2] 그룹 생성기: 호스트 리스트를 받아 Ansible 그룹 구조 반환
  # ------------------------------------------------------------
  mkGroup = hosts: {
    inherit hosts;
    vars = {
      # 그룹별 공통 변수
    };
  };

  # [3] 중간 데이터 가공
  # ------------------------------------------------------------
  masterHosts = k8s.masters;
  workerHosts = k8s.workerOrder;
  allNodes = masterHosts ++ workerHosts;
in {
  # Ansible이 요구하는 최종 JSON 구조
  # ------------------------------------------------------------

  # 모든 호스트의 상세 변수 정의
  _meta.hostvars = builtins.listToAttrs (map (name: {
      inherit name;
      value = toAnsibleHost name;
    })
    allNodes);

  # 글로벌 변수 (data/network.nix에서 직접 가져옴 - SSOT 준수)
  all = {
    children = ["k8s_masters" "k8s_workers"];
    vars = {
      # K8s Networking (Nix SSOT -> Ansible Vars)
      pod_cidr = network.kubernetes.pod_cidr;
      service_cidr = network.kubernetes.service_cidr;
      api_vip = network.kubernetes.api_vip;
      api_vip_prefix_length = network.vlans.services.prefixLength;
      cilium_helm_version = network.kubernetes.cilium_helm_version;
      jump_host = jumpHost;
      jump_user = jumpUser;
    };
  };

  k8s_masters = mkGroup masterHosts;
  k8s_workers = mkGroup workerHosts;
}
