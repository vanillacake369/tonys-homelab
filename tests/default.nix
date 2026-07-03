# Guard tests: overlay 구조 및 topology 정합성 검증.
# Run: nix eval .#tests.summary --json
# Run verbose: nix eval .#tests.results --json | python3 -m json.tool
{
  lib,
  nixosConfigurations ? {},
}: let
  # --- Fixtures ---
  collectOverlays = import ../lib/collect-overlays.nix {inherit lib;};
  resolveNode = import ../lib/resolve-node.nix;
  discoverNodes = import ../lib/extract-filename.nix {inherit lib;};
  collected = collectOverlays ../atoms;
  topology = import ../network/topology.nix;
  inventory = import ../ansible/inventory.nix {};
  homelabConfig = nixosConfigurations.homelab-1.config or null;
  vmFileNames = discoverNodes ../nodes/vms;
  vmTopologyNames = builtins.attrNames topology.vms;
  k8sOverlayText = builtins.readFile ../atoms/k8s/k8s-tools.overlay.nix;
  readKeyLines = file:
    builtins.filter (key: key != "")
    (map (key: lib.removeSuffix "\r" key) (lib.splitString "\n" (builtins.readFile file)));
  ipadHomelabKeys = readKeyLines ../secrets/ipad-homelab.pub;

  unique = values: builtins.length values == builtins.length (lib.unique values);
  requiredVmFields = ["ip" "mac" "tapId" "host" "parentHost" "role" "cluster" "network" "mem" "vcpu" "diskSize"];
  allVmsHaveField = field: builtins.all (vm: builtins.hasAttr field vm) (builtins.attrValues topology.vms);
  vmNodeConfig = name: nixosConfigurations.${name}.config.node;

  extractOverlayVersion = let
    matches = builtins.match ".*version = \"([0-9]+\\.[0-9]+\\.[0-9]+)\";.*" k8sOverlayText;
  in
    if matches == null
    then builtins.throw "FAIL: tests: cannot parse Kubernetes overlay version"
    else builtins.head matches;

  # --- Assertion helper ---
  assert' = name: cond:
    if cond
    then {
      inherit name;
      pass = true;
    }
    else builtins.throw "FAIL: ${name}";

  # =========================================================================
  # 1. Overlay Discovery
  # =========================================================================
  overlayTests = [
    (assert' "overlays: finds overlay files" (builtins.length collected > 0))
    (assert' "overlays: all are functions" (builtins.all builtins.isFunction collected))
    (assert' "overlays: expected count" (builtins.length collected == 3))
  ];

  # =========================================================================
  # 2. Topology Integrity
  # =========================================================================
  topologyTests = [
    (assert' "topology: VM registry matches nodes/vms files" ((lib.sort builtins.lessThan vmTopologyNames) == (lib.sort builtins.lessThan vmFileNames)))
    (assert' "topology: k8s api_vip defined" (topology.kubernetes ? api_vip))
    (assert' "topology: k8s version defined" (topology.kubernetes ? version))
    (assert' "topology: cilium_helm_version defined" (topology.kubernetes ? cilium_helm_version))
    (assert' "topology: cilium version is 1.19.x" (lib.hasPrefix "1.19" topology.kubernetes.cilium_helm_version))
    (assert' "topology: k8s version matches nix overlay" (topology.kubernetes.version == extractOverlayVersion))
    (assert' "topology: k8s version exported to ansible inventory" (inventory.all.vars.k8s_version == topology.kubernetes.version))
    (assert' "topology: vms have required fields" (builtins.all allVmsHaveField requiredVmFields))
    (assert' "topology: VM IPs are unique" (unique (map (vm: vm.ip) (builtins.attrValues topology.vms))))
    (assert' "topology: VM MACs are unique" (unique (map (vm: vm.mac) (builtins.attrValues topology.vms))))
    (assert' "topology: VM tap IDs are unique" (unique (map (vm: vm.tapId) (builtins.attrValues topology.vms))))
    (assert' "topology: hosts have required fields" (builtins.all (h: h ? ip && h ? user) (builtins.attrValues topology.hosts)))
    (assert' "topology: VM parent hosts exist" (builtins.all (vm: builtins.hasAttr vm.parentHost topology.hosts) (builtins.attrValues topology.vms)))
    (assert' "topology: VM legacy host matches parentHost" (builtins.all (vm: vm.host == vm.parentHost) (builtins.attrValues topology.vms)))
    (assert' "topology: VM networks exist on parent hosts" (builtins.all (vm: builtins.hasAttr vm.network topology.hosts.${vm.parentHost}.vlans) (builtins.attrValues topology.vms)))
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
    (assert' "topology: ansible master group matches topology roles" (
      lib.sort builtins.lessThan inventory.k8s_masters.hosts
      == lib.sort builtins.lessThan (builtins.filter (name: topology.vms.${name}.role == "k8s-master") vmTopologyNames)
    ))
    (assert' "topology: ansible worker group matches topology roles" (
      lib.sort builtins.lessThan inventory.k8s_workers.hosts
      == lib.sort builtins.lessThan (builtins.filter (name: topology.vms.${name}.role == "k8s-worker") vmTopologyNames)
    ))
    (assert' "topology: ansible inventory has no unknown role or vlan" (builtins.all (hostvars: hostvars.node_role != "unknown" && hostvars.node_vlan != "unknown") (builtins.attrValues inventory._meta.hostvars)))
    (assert' "topology: resolve-node uses declared VM parent" (builtins.all (name: let
      resolved = resolveNode {node = name;};
      parent = topology.hosts.${topology.vms.${name}.parentHost};
    in
      resolved.parentIp == parent.ip && resolved.parentUser == parent.user)
    (builtins.attrNames topology.vms)))
  ];

  # =========================================================================
  # 3. Remote iPad Access Guardrails
  # =========================================================================
  remoteAccessTests = lib.optionals (homelabConfig != null) [
    (assert' "remote-access: users are declarative" (!homelabConfig.users.mutableUsers))
    (assert' "remote-access: root password comes from sops" (homelabConfig.users.users.root.hashedPasswordFile == homelabConfig.sops.secrets."users/rootPassword".path))
    (assert' "remote-access: homelab deployment user remains limjihoon" (homelabConfig.node.user == "limjihoon"))
    (assert' "remote-access: remote user is not declared" (!(homelabConfig.users.users ? remote)))
    (assert' "remote-access: ipad homelab keys are assigned to limjihoon" (builtins.all (key: builtins.elem key homelabConfig.users.users.limjihoon.openssh.authorizedKeys.keys) ipadHomelabKeys))
    (assert' "remote-access: ipad homelab keys are not assigned to root" (builtins.all (key: !(builtins.elem key homelabConfig.users.users.root.openssh.authorizedKeys.keys)) ipadHomelabKeys))
    (assert' "remote-access: tailscale remains enabled" homelabConfig.services.tailscale.enable)
    (assert' "remote-access: tailscale ssh flag is removed" (!(builtins.elem "--ssh" homelabConfig.services.tailscale.extraSetFlags)))
  ];

  # =========================================================================
  allTests = overlayTests ++ topologyTests ++ remoteAccessTests;
in {
  results = allTests;
  summary = {
    total = builtins.length allTests;
    passed = builtins.length (builtins.filter (t: t.pass) allTests);
  };
}
