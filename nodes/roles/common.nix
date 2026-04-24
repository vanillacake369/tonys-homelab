# 모든 homelab 노드가 가져야 할 공통 Atom 전략
{
  config,
  lib,
  pkgs,
  ...
}: {
  system.stateVersion = "24.11";

  # VM 노드는 프로비저닝 시 디스크 크기 확장을 위해 자동 파티션 확장 활성화
  boot.growPartition = lib.mkIf (config.node.hostType == "vm") true;

  # VM 부팅 시 필요한 가상화 드라이버 명시
  boot.initrd.availableKernelModules = lib.mkIf (config.node.hostType == "vm") [
    "virtio_net"
    "virtio_pci"
    "virtio_mmio"
    "virtio_blk"
    "virtio_scsi"
    "9p"
    "9pnet_virtio"
  ];

  # 모든 사용자의 기본 쉘을 fish로 설정 (VM의 root 사용자 포함)
  users.defaultUserShell = pkgs.fish;

  # root 사용자 비밀번호 (SOPS)
  sops.secrets."users/rootPassword" = {
    neededForUsers = true;
  };
  users.users.root.hashedPasswordFile = config.sops.secrets."users/rootPassword".path;

  # Bash로 접속하더라도 fish로 자동 전환되도록 설정 (optional, but robust)
  programs.bash.interactiveShellInit = ''
    if [[ $([[ -t 0 ]] && echo 1) -eq 1 ]]; then
      exec ${pkgs.fish}/bin/fish
    fi
  '';

  imports = [
    ../../atoms/system/sops.nix
    ../../atoms/system/nix.nix
    ../../atoms/system/locale.nix
    ../../atoms/system/timesyncd.nix
    ../../atoms/system/shell.nix
    ../../atoms/system/cli-tools.nix
    ../../atoms/network/ssh-server.nix
    ../../atoms/network/network-base.nix
    ../../atoms/system/authorized-keys.nix
  ];
}
