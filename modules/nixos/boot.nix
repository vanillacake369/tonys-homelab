# Boot loader configuration for server
_: {
  boot = {
    loader = {
      # grub = {
      #   efiSupport = true;
      #   efiInstallAsRemovable = true;
      # };
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    # KVM 모듈 로드 및 가상화 지원
    # AMD CPU 라면 "kvm-adm"
    kernelModules = [
      "kvm-amd"
      "vhost_net"
    ];
    blacklistedKernelModules = [
      "snd_hda_intel"
      "bluetooth"
    ];
    kernelParams = [
      # "intel_iommu=on"
      "amd_iommu=on"
      "iommu=pt"
    ];
  };
  # 가상화 관련 추가 설정
  virtualisation.libvirtd.enable = true;
}
