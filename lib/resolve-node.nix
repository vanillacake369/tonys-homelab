# lib/resolve-node.nix
# 노드 이름 → {ip, user, type, parentIp, parentUser} 해석
# justfile 등 외부 도구에서 노드 접속 정보를 동적으로 얻기 위한 순수 Nix 헬퍼
{node}: let
  topology = import ../network/topology.nix;
  isHost = builtins.hasAttr node topology.hosts;
  isVM = builtins.hasAttr node topology.vms;

  hostInfo = {
    ip = topology.hosts.${node}.ip;
    user = topology.hosts.${node}.user;
    type = "physical";
    parentIp = null;
    parentUser = null;
  };

  vmInfo = let
    vm = topology.vms.${node};
    parentName = vm.parentHost;
    parent =
      if builtins.hasAttr parentName topology.hosts
      then topology.hosts.${parentName}
      else builtins.throw "VM ${node} references unknown parent host ${parentName}";
  in {
    ip = vm.ip;
    user = "root";
    type = "vm";
    parentIp = parent.ip;
    parentUser = parent.user;
  };
in
  if isHost
  then hostInfo
  else if isVM
  then vmInfo
  else builtins.throw "Unknown node: ${node}"
