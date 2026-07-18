import ../../lib/mk-k8s-vm-node.nix {
  name = "k8s-worker-2";
  roleModule = ../roles/k8s-worker.nix;
}
