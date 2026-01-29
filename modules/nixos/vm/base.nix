# VM 공통 설정 모듈
# 비-K8s VM들 (vault, jenkins, registry)에서 공유되는 설정
{...}: {
  imports = [
    ../packages/base.nix
    ../packages/shell.nix
    ../packages/editor.nix
    ../packages/monitoring.nix
    ../packages/network-tools.nix
    ../packages/dev-tools.nix
    ../packages/hardware-diag.nix
    ../packages/gpu-diag.nix
    ../packages/virtualization.nix
    ../packages/terminal.nix
  ];

  # ============================================================
  # SSH 서비스 (hardened)
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
}
