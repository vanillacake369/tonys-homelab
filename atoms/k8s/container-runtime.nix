# Atoms: Container Runtime
# Kernel modules and Containerd engine.
{ ... }: {
  boot.kernelModules = [ "overlay" "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
    };
  };
}
