# nodes/roles/common.nix
# 모든 homelab 노드가 가져야 할 공통 Atom 전략
{...}: {
  system.stateVersion = "24.11";

  imports = [
    ../../atoms/system/nix.nix
    ../../atoms/system/locale.nix
    ../../atoms/system/shell.nix
    ../../atoms/system/cli-tools.nix
    ../../atoms/network/ssh-server.nix
    ../../atoms/network/network-base.nix
    ../../atoms/system/authorized-keys.nix
  ];
}
