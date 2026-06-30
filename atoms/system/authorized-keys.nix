# Atom: SSH Authorized Keys
# homelab 인프라 접근 공개키 선언
# - 물리 호스트 및 모든 VM에 공통 적용 (common.nix 경유)
# - 공개키이므로 암호화 불필요 (비공개키는 secrets/에서 sops-nix로 관리)
{
  config,
  lib,
  ...
}: let
  # 파일이 있으면 읽어오고, 없으면 빈 리스트 반환 (안전장치)
  readKey = file:
    if builtins.pathExists file
    then [(lib.removeSuffix "\n" (builtins.readFile file))]
    else [];

  infraKeys =
    (readKey ../../secrets/limjihoon.pub)
    ++ (readKey ../../secrets/homelab-1.pub);

  ipadHomelabKeys = readKey ../../secrets/ipad-homelab.pub;
in {
  users.users = lib.mkMerge [
    {
      root.openssh.authorizedKeys.keys = infraKeys;
    }
    (lib.mkIf (config.node.user != "root") {
      "${config.node.user}".openssh.authorizedKeys.keys =
        infraKeys
        ++ lib.optionals (config.node.hostType == "physical") ipadHomelabKeys;
    })
  ];
}
