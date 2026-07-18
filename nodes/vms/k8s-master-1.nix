import ../../lib/mk-k8s-vm-node.nix {
  name = "k8s-master-1";
  roleModule = ../roles/k8s-master.nix;
}
