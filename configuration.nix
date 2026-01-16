# Main NixOS configuration for homelab server
# This replaces Proxmox on bare-metal server
{
  # `modulesPath`는 NixOS 설정 시스템(`nixpkgs`)에서
  # 기본적으로 제공하는 내장 모듈들이 위치한 경로
  modulesPath,
  ...
}: {
  imports = [
    # 시스템에 설치된 커널 모듈 중
    # NixOS가 자동으로 감지하지 못했을 하드웨어 드라이버들을 보완
    (modulesPath + "/installer/scan/not-detected.nix")
    # 현재 시스템이 QEMU/KVM 위에서 작동할 때
    # 필요한 최적화 설정을 불러옴
    # (modulesPath + "/profiles/qemu-guest.nix")

    # Disko disk partitioning
    ./disko-config.nix

    # System modules (NixOS only)
    ./modules/nixos/boot.nix
    ./modules/nixos/locale.nix
    ./modules/nixos/network.nix
    ./modules/nixos/ssh.nix
    ./modules/nixos/sops.nix
    ./modules/nixos/nix-settings.nix
    ./modules/nixos/users.nix
  ];

  # NixOS version
  system.stateVersion = "24.11";
}
