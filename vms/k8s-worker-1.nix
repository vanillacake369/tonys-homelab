# TODO : 예시코드. 실제 구성도에 맞춰 수정할 것
# {
#   microvm = {
#     hypervisor = "qemu"; # GPU 패스스루는 qemu가 안정적
#     vcpu = 4;
#     mem = 8192;
#     # iGPU PCI 주소 할당 (예시: 0000:c1:00.0)
#     qemu.extraArgs = ["-device" "vfio-pci,host=c1:00.0"];
#
#     interfaces = [
#       {
#         type = "bridge";
#         id = "vm-worker1";
#         bridge = "vmbr1";
#       }
#     ];
#   };
# }
