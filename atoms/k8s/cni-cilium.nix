# Atoms: CNI (Cilium)
# CNI (Cilium) specific OS requirements (BPF, Cgroupv2).
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    cilium-cli
  ];

  fileSystems."/run/cilium/cgroupv2" = {
    device = "none";
    fsType = "cgroup2";
    options = ["rw" "nosuid" "nodev" "noexec" "relatime"];
  };
  # BPF filesystem — Cilium + kubelet 공통 의존
  # NOTE: kubelet-service.nix에서 sys-fs-bpf.mount를 after/wants로 참조
  fileSystems."/sys/fs/bpf" = {
    device = "bpffs";
    fsType = "bpf";
    options = ["rw" "nosuid" "nodev" "noexec" "relatime" "mode=700"];
  };
  systemd.tmpfiles.rules = [
    "d /run/cilium/cgroupv2 0755 root root - -"
    "d /etc/cni/net.d 0755 root root - -"
  ];
}
