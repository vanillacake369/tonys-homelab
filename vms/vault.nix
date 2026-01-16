# TODO : 예시코드. 실제 구성도에 맞춰 수정할 것
# {
#   microvm = {
#     vcpu = 2;
#     mem = 2048;
#     hypervisor = "cloud-hypervisor"; # 또는 qemu
#
#     # 스토리지 설정 (NVMe 활용)
#     shares = [
#       {
#         source = "/var/lib/microvms/vault/storage";
#         mountPoint = "/var/lib/vault";
#         tag = "vault-storage";
#         proto = "virtiofs";
#       }
#     ];
#
#     # 네트워크 설정 (VLAN 10 예시)
#     interfaces = [
#       {
#         type = "bridge";
#         id = "vm-vault";
#         bridge = "vmbr1";
#         # VLAN Tagging은 브릿지 레벨이나 OPNsense에서 관리하거나
#         # 여기서 macvtap 등을 활용할 수 있습니다.
#       }
#     ];
#   };
#
#   # Vault 서비스 설정
#   services.vault.enable = true;
#   networking.hostName = "vault";
# }
