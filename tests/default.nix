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
  projections = import ../network/projections.nix {inherit topology;};
  k8sPorts = import ../atoms/k8s/ports.nix;
  inventory = import ../ansible/inventory.nix {};
  homelabConfig = nixosConfigurations.homelab-1.config or null;
  vmFileNames = discoverNodes ../nodes/vms;
  vmTopologyNames = builtins.attrNames topology.vms;
  hostTopologyNames = builtins.attrNames topology.hosts;
  k8sOverlayText = builtins.readFile ../atoms/k8s/k8s-distro-compat.overlay.nix;
  lbIpPoolText = builtins.readFile ../deploy/k8s/infrastructure/networking/lb-ippool.yaml;
  bookorbitWorkloadTexts = map builtins.readFile [
    ../deploy/k8s/apps/bookorbit/deployment.yaml
    ../deploy/k8s/apps/bookorbit/postgres-statefulset.yaml
    ../deploy/k8s/apps/bookorbit/setup-job.yaml
  ];
  readKeyLines = file:
    if builtins.pathExists file
    then
      builtins.filter (key: key != "")
      (map (key: lib.removeSuffix "\r" key) (lib.splitString "\n" (builtins.readFile file)))
    else [];
  topLevelSecretPublicKeys =
    builtins.filter
    (name: lib.hasSuffix ".pub" name)
    (builtins.attrNames (builtins.readDir ../secrets));
  hostLoginKeys =
    (readKeyLines ../secrets/hosts/host-homelab-1-ed25519.pub)
    ++ (readKeyLines ../secrets/hosts/host-homelab-2-ed25519.pub);
  mobileHomelabKeys =
    (readKeyLines ../secrets/users/user-ipad-homelab-ed25519.pub)
    ++ (readKeyLines ../secrets/users/user-iphone-homelab-ed25519.pub);
  hostIdentityKeyFiles =
    builtins.filter
    (name: lib.hasInfix "ssh_host" name && lib.hasSuffix ".pub" name)
    (builtins.attrNames (builtins.readDir ../secrets/hosts));
  hostIdentityKeys =
    builtins.concatLists (map (name: readKeyLines (../secrets/hosts + "/${name}")) hostIdentityKeyFiles);

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
  overlayTests = import ./overlays.nix {
    inherit assert' collected;
  };

  # =========================================================================
  # 2. Topology Integrity
  # =========================================================================
  topologyTests = import ./topology.nix {
    inherit
      lib
      assert'
      nixosConfigurations
      topology
      projections
      k8sPorts
      inventory
      resolveNode
      vmFileNames
      vmTopologyNames
      hostTopologyNames
      k8sOverlayText
      lbIpPoolText
      bookorbitWorkloadTexts
      ;
  };

  # =========================================================================
  # 3. Remote iPad Access Guardrails
  # =========================================================================
  remoteAccessTests =
    lib.optionals (homelabConfig != null)
    (import ./remote-access.nix {
      inherit
        assert'
        homelabConfig
        topLevelSecretPublicKeys
        hostLoginKeys
        mobileHomelabKeys
        hostIdentityKeys
        ;
    });

  # =========================================================================
  allTests = overlayTests ++ topologyTests ++ remoteAccessTests;
in {
  results = allTests;
  summary = {
    total = builtins.length allTests;
    passed = builtins.length (builtins.filter (t: t.pass) allTests);
  };
}
