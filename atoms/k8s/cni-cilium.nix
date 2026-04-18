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
  fileSystems."/sys/fs/bpf" = {
    device = "bpffs";
    fsType = "bpf";
  };
  systemd.tmpfiles.rules = [
    "d /run/cilium/cgroupv2 0755 root root - -"
  ];
}
