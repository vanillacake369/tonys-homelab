# VFIO GPU Passthrough 설정 모듈
# homelabConstants에서 GPU 설정을 읽어 부팅 시 vfio-pci 드라이버에 바인딩
{
  homelabConstants,
  lib,
  ...
}: let
  # GPU passthrough가 활성화된 VM 목록 추출
  vmsWithGpu = lib.filterAttrs
    (name: vm: (vm.gpu.enable or false))
    homelabConstants.vms;

  # GPU가 하나라도 있는지 확인
  hasGpuPassthrough = vmsWithGpu != {};

  # 모든 GPU의 PCI ID 수집 (vfio-pci.ids= 파라미터용)
  gpuPciIds = lib.concatStringsSep ","
    (lib.mapAttrsToList (name: vm: vm.gpu.pciId) vmsWithGpu);
in {
  config = lib.mkIf hasGpuPassthrough {
    boot = {
      # VFIO 모듈을 initrd에서 조기 로딩 (GPU 드라이버보다 먼저)
      initrd.kernelModules = [
        "vfio_pci"
        "vfio"
        "vfio_iommu_type1"
      ];

      # GPU를 vfio-pci에 바인딩하는 커널 파라미터
      kernelParams = [
        "vfio-pci.ids=${gpuPciIds}"
      ];

      # amdgpu가 이 GPU를 먼저 잡지 못하도록 방지
      # (vfio-pci.ids가 우선하지만 안전을 위해 추가)
      extraModprobeConfig = ''
        softdep amdgpu pre: vfio-pci
      '';
    };

    # VFIO 장치에 대한 권한 설정 (MicroVM이 접근 가능하도록)
    # microvm 사용자/kvm 그룹이 /dev/vfio/* 장치에 접근 가능
    services.udev.extraRules = ''
      # VFIO 장치를 kvm 그룹에 허용
      SUBSYSTEM=="vfio", OWNER="root", GROUP="kvm", MODE="0660"
    '';

    # microvm 사용자를 kvm 그룹에 추가
    users.users.microvm.extraGroups = ["kvm"];
  };
}
