# Atoms: SSH Client (Host to VM Access)
{lib, ...}: let
  network = import ../../network/topology.nix;
  vmHosts = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: vm: ''
      Host ${name}
        HostName ${vm.ip}
    '')
    network.vms);
in {
  programs.ssh.extraConfig = ''
    # Global VM defaults
    Host 10.0.20.* k8s-master-* k8s-worker-*
      User root
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null

    # Topology-derived VM hosts
    ${vmHosts}
  '';
}
