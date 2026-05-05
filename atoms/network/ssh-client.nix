# Atoms: SSH Client (Host to VM Access)
# VM IP는 nodes/vms/*.nix 에 인라인 선언된 값과 동기화
{...}: {
  programs.ssh.extraConfig = ''
    # Global VM defaults
    Host 10.0.20.* k8s-master-* k8s-worker-*
      User root
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null

    # Static Host Definitions
    Host k8s-master-1
      HostName 10.0.20.10
    Host k8s-worker-1
      HostName 10.0.20.21
    Host k8s-worker-2
      HostName 10.0.20.22
  '';
}
