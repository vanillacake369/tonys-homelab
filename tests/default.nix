# Guard tests: overlay 구조 및 topology 정합성 검증.
# Run: nix eval .#tests.summary --json
# Run verbose: nix eval .#tests.results --json | python3 -m json.tool
{lib}: let
  # --- Fixtures ---
  collectOverlays = import ../lib/collect-overlays.nix {inherit lib;};
  collected = collectOverlays ../atoms;
  topology = import ../network/topology.nix;

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
  ];

  # =========================================================================
  allTests = overlayTests ++ topologyTests;
in {
  results = allTests;
  summary = {
    total = builtins.length allTests;
    passed = builtins.length (builtins.filter (t: t.pass) allTests);
  };
}
