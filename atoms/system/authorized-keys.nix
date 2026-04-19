# Atom: SSH Authorized Keys
# homelab 인프라 접근 공개키 선언
# - 물리 호스트 및 모든 VM에 공통 적용 (common.nix 경유)
# - 공개키이므로 암호화 불필요 (비공개키는 secrets/에서 sops-nix로 관리)
{
  config,
  lib,
  ...
}: let
  keys = [
    # tonys-mac.local (Mac 개발 머신)
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDXaiGyBrABSefb5cDj1W3FFCIu1/yDlbZ/e+icx6MgXI2w6+p5Qkt052xLgl5jvLu2IQFOapdxYgZ6t5I1Fnp0+qquGdy+1ZNsMW6SLwZsQcx0OQSlzFkkGyd4I17GesEFWY1t/eOLvRfmQ0H0n6R99EJ5Zp9HzbcjO3AZrWaVDwpTFPOIW4Vac9PKyxDddVfFf+/qXqiWDEPrLt+RugbW8vIwDXGb+qPblUZlIOV0qwYjxrJo3bT2S1nSmmKgDuzPcsl7KlOXix+NmRAUmDD6dnh4Z6zamrGI3l63C1785Is77yN3msVFP/iUToQPVeyNehoWIAx/nd1uDdnvG6FgAdAvAryKdnotI6o1tOpqn0DV0Fo675Tb1p7HC1OzVhmTzr57ng+o1rWIZS7rxEEmUh/1pdL/tUP+hRD4jQKwiRr7QYWI+KXZmxKi0jsbp+wvPhi2XNMpuGTP4ErhLnD1GgHGC0nIyRX9okGLAb0gIPIMosaWAqq1On91gMQn2D/8RJ1UCwKmpH6UmsAS3ZiksnJNjHEF/nVWpymMpjYeYh6HnageVBhi2zKDlkpYCwYgE+RZ6CUxOWkKbCjm+Z8DTc02x+OhnRDUysU41P3QPBfaAkAiL0QW8aDRQDV26MywdBxq84ZT94VxzGcZr4N3SvMXe4Jv9znpZREPIqJjDQ== limjihoon@tonys-mac.local"

    # homelab-1 (물리 호스트) → VM 접근 (Ansible ProxyJump 기반)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgKsYPtQJYXLQweE0n3bRo1wkNhsNIjbBaA+D1R0/fc limjihoon@homelab-1"
  ];
in {
  users.users = lib.mkMerge [
    {
      root.openssh.authorizedKeys.keys = keys;
    }
    (lib.mkIf (config.node.user != "root") {
      "${config.node.user}".openssh.authorizedKeys.keys = keys;
    })
  ];
}
