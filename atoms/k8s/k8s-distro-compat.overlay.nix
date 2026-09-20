# Pin K8s tools to match desired cluster version (network/topology.nix: kubernetes.version).
# Prevents nixpkgs-unstable from upgrading kubectl/kubeadm beyond cluster's ±1 minor skew.
let
  topology = import ../../network/topology.nix;
in
  _: prev: {
    kubernetes = prev.kubernetes.overrideAttrs (_: rec {
      version = topology.kubernetes.version;
      src = prev.fetchFromGitHub {
        owner = "kubernetes";
        repo = "kubernetes";
        tag = "v${version}";
        hash = "sha256-woIp7AnW7r3y0rpKO03+0t6ONyNXTS1IYxW40E1O8DA=";
      };
    });
  }
