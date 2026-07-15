# Pin K8s tools to match cluster version (ansible/group_vars/all.yml: k8s_version).
# Prevents nixpkgs-unstable from upgrading kubectl/kubeadm beyond cluster's ±1 minor skew.
_: prev: {
  kubernetes = prev.kubernetes.overrideAttrs (_: rec {
    version = "1.35.3";
    src = prev.fetchFromGitHub {
      owner = "kubernetes";
      repo = "kubernetes";
      tag = "v${version}";
      hash = "sha256-woIp7AnW7r3y0rpKO03+0t6ONyNXTS1IYxW40E1O8DA=";
    };
  });
}
