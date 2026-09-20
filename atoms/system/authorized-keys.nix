# Atom: SSH Authorized Keys
# homelab 인프라 접근 공개키 선언
# - 물리 호스트 및 모든 VM에 공통 적용 (nodes/profiles/base.nix 경유)
# - 공개키이므로 암호화 불필요 (비공개키는 secrets/에서 sops-nix로 관리)
{
  config,
  lib,
  ...
}: let
  # 파일이 있으면 줄 단위 공개키 목록으로 읽어오고, 없으면 빈 리스트 반환 (안전장치)
  readKey = file:
    if builtins.pathExists file
    then
      builtins.filter (key: key != "")
      (map (key: lib.removeSuffix "\r" key) (lib.splitString "\n" (builtins.readFile file)))
    else [];

  infraKeys =
    (readKey ../../secrets/users/user-limjihoon-ed25519.pub)
    ++ (readKey ../../secrets/hosts/host-homelab-1-ed25519.pub)
    ++ (readKey ../../secrets/hosts/host-homelab-2-ed25519.pub);

  mobileHomelabKeys =
    (readKey ../../secrets/users/user-ipad-homelab-ed25519.pub)
    ++ (readKey ../../secrets/users/user-iphone-homelab-ed25519.pub);
in {
  users.users = lib.mkMerge [
    {
      root.openssh.authorizedKeys.keys = infraKeys;
    }
    (lib.mkIf (config.node.user != "root") {
      "${config.node.user}".openssh.authorizedKeys.keys =
        infraKeys
        ++ lib.optionals (config.node.hostType == "physical") mobileHomelabKeys;
    })
  ];
}
