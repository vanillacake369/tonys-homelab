# VM 공통 설정 모듈
# 비-K8s VM들 (vault, jenkins, registry)에서 공유되는 설정
{
  lib,
  homelabConstants,
  ...
}: {
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
