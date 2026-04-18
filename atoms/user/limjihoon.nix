# Atom: limjihoon 사용자
# 물리 호스트에서 import하여 사용 (VM은 root 사용)
{pkgs, ...}: {
  users.users.limjihoon = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcONXeiPvvYoH/EYMU8y2EUjVRPjhL/QfNiI7n6iy9u limjihoon@tonys-mac.local"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
}
