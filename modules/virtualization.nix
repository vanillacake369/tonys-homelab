# Virtualization configuration (replaces Proxmox functionality)
{pkgs, ...}: {
  virtualisation = {
    # Enable libvirtd for KVM/QEMU VMs
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    # Enable Podman for containers (Docker-compatible)
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Install virt-manager and other useful tools
  environment.systemPackages = with pkgs; [
    virt-manager
    qemu
    OVMF
  ];
}
