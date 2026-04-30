# Atoms: Container Runtime
# Kernel modules and Containerd engine.
{pkgs, ...}: {
  boot.kernelModules = ["overlay" "br_netfilter"];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;
      # K8s 1.35.x 기본 pause 이미지 — containerd 기본값과 버전 불일치 방지
      plugins."io.containerd.grpc.v1.cri".sandbox_image = "registry.k8s.io/pause:3.10";
      # Cilium CNI는 /opt/cni/bin에 바이너리, /etc/cni/net.d에 설정을 설치
      plugins."io.containerd.grpc.v1.cri".cni.bin_dir = "/opt/cni/bin";
      plugins."io.containerd.grpc.v1.cri".cni.conf_dir = "/etc/cni/net.d";
    };
  };
  systemd.services.containerd.serviceConfig = {
    PrivateMounts = false;
  };
}
