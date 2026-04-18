# Atom: SSH Authorized Keys
# homelab 인프라 접근 공개키 선언
# - 물리 호스트 및 모든 VM에 공통 적용 (common.nix 경유)
# - 공개키이므로 암호화 불필요 (비공개키는 secrets/에서 sops-nix로 관리)
#
# 키 목록:
#   1. tonys-mac.local  - 개발 머신 (Mac) → homelab 직접 접근
#   2. homelab-1        - 물리 호스트 → VM 접근 (Ansible ProxyJump 기반)
{...}: {
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcONXeiPvvYoH/EYMU8y2EUjVRPjhL/QfNiI7n6iy9u limjihoon@tonys-mac.local"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgKsYPtQJYXLQweE0n3bRo1wkNhsNIjbBaA+D1R0/fc limjihoon@homelab-1"
  ];
}
