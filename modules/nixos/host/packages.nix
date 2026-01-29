# 호스트 전용 패키지
# 모든 패키지 모듈을 import하여 호스트에 설치
{...}: {
  imports = [
    ../packages/base.nix
    ../packages/shell.nix
    ../packages/editor.nix
    ../packages/monitoring.nix
    ../packages/network-tools.nix
    ../packages/dev-tools.nix
    ../packages/hardware-diag.nix
    ../packages/gpu-amd.nix
    ../packages/gpu-diag.nix
    ../packages/virtualization.nix
    ../packages/terminal.nix
    ../packages/misc.nix
  ];
}
