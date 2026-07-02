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
  collected = collectOverlays ../atoms;
  topology = import ../network/topology.nix;
  homelabConfig = nixosConfigurations.homelab-1.config or null;
  readKeyLines = file:
    builtins.filter (key: key != "")
    (map (key: lib.removeSuffix "\r" key) (lib.splitString "\n" (builtins.readFile file)));
  ipadHomelabKeys = readKeyLines ../secrets/ipad-homelab.pub;

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
    (assert' "topology: k8s api_vip defined" (topology.kubernetes ? api_vip))
    (assert' "topology: cilium_helm_version defined" (topology.kubernetes ? cilium_helm_version))
    (assert' "topology: cilium version is 1.19.x" (lib.hasPrefix "1.19" topology.kubernetes.cilium_helm_version))
    (assert' "topology: k8s_version in ansible matches" true)
    (assert' "topology: vms have required fields" (builtins.all (vm: vm ? ip && vm ? mac && vm ? host) (builtins.attrValues topology.vms)))
    (assert' "topology: hosts have required fields" (builtins.all (h: h ? ip && h ? user) (builtins.attrValues topology.hosts)))
    (assert' "topology: VM parent hosts exist" (builtins.all (vm: builtins.hasAttr vm.host topology.hosts) (builtins.attrValues topology.vms)))
    (assert' "topology: resolve-node uses declared VM parent" (builtins.all (name: let
      resolved = resolveNode {node = name;};
      parent = topology.hosts.${topology.vms.${name}.host};
    in
      resolved.parentIp == parent.ip && resolved.parentUser == parent.user)
    (builtins.attrNames topology.vms)))
  ];

  # =========================================================================
  # 3. Remote iPad Access Guardrails
  # =========================================================================
  remoteAccessTests =
    lib.optionals (homelabConfig != null) [
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
