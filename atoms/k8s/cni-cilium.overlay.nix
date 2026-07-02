# Pin cilium-cli to match deployed Cilium version (network/topology.nix: cilium_helm_version).
# Prevents CLI/controller version mismatch that can break cilium status/connectivity test.
_: prev: {
  cilium-cli = prev.cilium-cli.overrideAttrs (_: rec {
    version = "0.19.2";
    src = prev.fetchFromGitHub {
      owner = "cilium";
      repo = "cilium-cli";
      tag = "v${version}";
      hash = "sha256-zlPl6J+Vbv2An1bauzhee8hrtEEg1ENR6SKSzv3PCS0=";
    };
  });
}
