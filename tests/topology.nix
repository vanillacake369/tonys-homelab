{
  lib,
  assert',
  nixosConfigurations,
  topology,
  projections,
  k8sPorts,
  inventory,
  resolveNode,
  vmFileNames,
  vmTopologyNames,
  hostTopologyNames,
  k8sOverlayText,
  lbIpPoolText,
  bookorbitWorkloadTexts,
}: let
  unique = values: builtins.length values == builtins.length (lib.unique values);
  requiredVmFields = ["ip" "mac" "tapId" "parentHost" "role" "cluster" "network" "mem" "vcpu" "diskSize"];
  allVmsHaveField = field: builtins.all (vm: builtins.hasAttr field vm) (builtins.attrValues topology.vms);
  isK8sRole = role: role == "k8s-master" || role == "k8s-worker";
  k8sVmNames =
    builtins.filter
    (name: topology.vms.${name}.cluster == topology.kubernetes.cluster && isK8sRole topology.vms.${name}.role)
    vmTopologyNames;
  k8sHostNames =
    builtins.filter
    (name:
      topology.hosts.${name}
      ? cluster
      && topology.hosts.${name}.cluster == topology.kubernetes.cluster
      && isK8sRole topology.hosts.${name}.role)
    hostTopologyNames;
  k8sNodeNames = k8sVmNames ++ k8sHostNames;
  k8sNodeRole = name:
    if builtins.hasAttr name topology.vms
    then topology.vms.${name}.role
    else topology.hosts.${name}.role;
  vmNodeConfig = name: nixosConfigurations.${name}.config.node;
  hostNodeConfig = name: nixosConfigurations.${name}.config.node;
  localPath = topology.storage.localPath;
  localPathNodeLabelArg = "--node-labels=${lib.concatStringsSep "," (lib.mapAttrsToList (name: value: "${name}=${value}") localPath.nodeSelector)}";
  localPathSelectorYaml = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "        ${name}: ${value}") localPath.nodeSelector);
  kubeletEnvironment = name: nixosConfigurations.${name}.config.systemd.services.kubelet.serviceConfig.Environment or [];
in [
  (assert' "topology: VM registry matches nodes/vms files" ((lib.sort builtins.lessThan vmTopologyNames) == (lib.sort builtins.lessThan vmFileNames)))
  (assert' "topology: k8s api_vip defined" (topology.kubernetes ? api_vip))
  (assert' "topology: k8s version defined" (topology.kubernetes ? version))
  (assert' "topology: cilium_helm_version defined" (topology.kubernetes ? cilium_helm_version))
  (assert' "topology: cilium version is 1.19.x" (lib.hasPrefix "1.19" topology.kubernetes.cilium_helm_version))
  (assert' "topology: k8s overlay consumes topology version" (lib.hasInfix "version = topology.kubernetes.version" k8sOverlayText))
  (assert' "topology: k8s version exported to ansible inventory" (inventory.all.vars.k8s_version == topology.kubernetes.version))
  (assert' "topology: k8s master ports are centralized" (k8sPorts.masterTcp == [6443 2379 2380 10250 10251 10252]))
  (assert' "topology: k8s worker ports are centralized" (k8sPorts.workerTcp == [10250]))
  (assert' "topology: lb pool matches Cilium LB-IPAM manifest" (lib.hasInfix "cidr: ${topology.kubernetes.lb_pool}" lbIpPoolText))
  (assert' "topology: local-path data nodes exist" (builtins.all (name: builtins.hasAttr name topology.vms) localPath.dataNodes))
  (assert' "topology: local-path data nodes are workers" (builtins.all (name: topology.vms.${name}.role == "k8s-worker") localPath.dataNodes))
  (assert' "topology: local-path data nodes get kubelet labels" (builtins.all (name:
    builtins.elem "KUBELET_TOPOLOGY_ARGS=${localPathNodeLabelArg}" (kubeletEnvironment name))
  localPath.dataNodes))
  (assert' "topology: non-storage nodes do not get local-path kubelet labels" (builtins.all (name:
    builtins.elem name localPath.dataNodes || !(builtins.elem "KUBELET_TOPOLOGY_ARGS=${localPathNodeLabelArg}" (kubeletEnvironment name)))
  vmTopologyNames))
  (assert' "topology: BookOrbit workloads target local-path node pool" (builtins.all (text: lib.hasInfix localPathSelectorYaml text) bookorbitWorkloadTexts))
  (assert' "topology: vms have required fields" (builtins.all allVmsHaveField requiredVmFields))
  (assert' "topology: VM IPs are unique" (unique (map (vm: vm.ip) (builtins.attrValues topology.vms))))
  (assert' "topology: VM MACs are unique" (unique (map (vm: vm.mac) (builtins.attrValues topology.vms))))
  (assert' "topology: VM tap IDs are unique" (unique (map (vm: vm.tapId) (builtins.attrValues topology.vms))))
  (assert' "topology: hosts have required fields" (builtins.all (h:
    h
    ? role
    && h
    ? user
    && h
    ? uplink
    && h.uplink
    ? interface
    && h.uplink
    ? ip
    && h.uplink
    ? prefixLength
    && h.uplink
    ? gateway)
  (builtins.attrValues topology.hosts)))
  (assert' "topology: k8s hosts declare cluster membership" (builtins.all (h: !(isK8sRole h.role) || h ? cluster) (builtins.attrValues topology.hosts)))
  (assert' "topology: VM parent hosts exist" (builtins.all (vm: builtins.hasAttr vm.parentHost topology.hosts) (builtins.attrValues topology.vms)))
  (assert' "topology: VM networks exist on parent hosts" (builtins.all (vm: builtins.hasAttr vm.network topology.hosts.${vm.parentHost}.vlans) (builtins.attrValues topology.vms)))
  (assert' "topology: projections.vmsForHost projects by parentHost" (builtins.all (hostName:
    builtins.all (vm: vm.parentHost == hostName) (builtins.attrValues (projections.vmsForHost hostName)))
  (builtins.attrNames topology.hosts)))
  (assert' "topology: NixOS VM node contracts match topology" (builtins.all (name: let
    vm = topology.vms.${name};
    node = vmNodeConfig name;
  in
    node.ip
    == vm.ip
    && node.mac == vm.mac
    && node.parentHost == vm.parentHost
    && node.role == vm.role)
  vmTopologyNames))
  (assert' "topology: NixOS physical host node roles match topology" (builtins.all (name: let
    host = topology.hosts.${name};
    node = hostNodeConfig name;
  in
    node.role == host.role)
  hostTopologyNames))
  (assert' "topology: ansible master group matches topology roles" (
    lib.sort builtins.lessThan inventory.k8s_masters.hosts
    == lib.sort builtins.lessThan (builtins.filter (name: k8sNodeRole name == "k8s-master") k8sNodeNames)
  ))
  (assert' "topology: ansible worker group matches topology roles" (
    lib.sort builtins.lessThan inventory.k8s_workers.hosts
    == lib.sort builtins.lessThan (builtins.filter (name: k8sNodeRole name == "k8s-worker") k8sNodeNames)
  ))
  (assert' "topology: ansible inventory has no unknown role or vlan" (builtins.all (hostvars: hostvars.node_role != "unknown" && hostvars.node_vlan != "unknown") (builtins.attrValues inventory._meta.hostvars)))
  (assert' "topology: ansible physical k8s hosts resolve through ssh config aliases" (builtins.all (name: !(inventory._meta.hostvars.${name} ? ansible_host)) k8sHostNames))
  (assert' "topology: resolve-node uses declared VM parent" (builtins.all (name: let
    resolved = resolveNode {node = name;};
    parent = topology.hosts.${topology.vms.${name}.parentHost};
  in
    resolved.parentIp == parent.uplink.ip && resolved.parentUser == parent.user)
  (builtins.attrNames topology.vms)))
]
