# 호스트 전용 패키지 (full 프로필)
{
  pkgs,
  data,
  ...
}: let
  resolvePackages = profileName:
    builtins.concatLists (
      map (g: (data.packages.groups.${g} or (_: [])) pkgs)
        (data.packages.profiles.${profileName} or data.packages.profiles.server)
    );
in {
  environment.systemPackages = resolvePackages "full";
}
