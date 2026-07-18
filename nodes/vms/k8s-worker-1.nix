import ../../lib/mk-k8s-vm-node.nix {
  name = "k8s-worker-1";
  roleModule = ../roles/k8s-worker.nix;
}
