# Kubernetes Worker Profile
{
  lib,
  data,
  microvmTarget,
  ...
}: let
  vmInfo = data.vms.definitions.${microvmTarget};
in {
  # Worker 전용 방화벽 설정
  networking.firewall.allowedTCPPortRanges = [
    {
      from = 30000;
      to = 32767;
    } # NodePort
  ];

  networking.firewall.allowedUDPPorts = [
    8472 # Flannel/Cilium VXLAN
  ];

  # GPU 설정 (데이터에 gpu.enable = true가 있을 경우)
  microvm.devices = lib.mkIf (vmInfo ? gpu && vmInfo.gpu.enable) [
    {
      bus = "pci";
      path = vmInfo.gpu.pciAddress;
    }
  ];
}
