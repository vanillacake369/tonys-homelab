# Home Manager 공용 모듈 생성기
{
  inputs,
  homelabConstants,
  specialArgs,
}:
{
  homeConfigPath,
  username ? homelabConstants.host.username,
  extraSpecialArgs ? {},
  useGlobalPkgs ? true,
  useUserPackages ? true,
  backupFileExtension ? "backup",
}: {
  imports = [inputs.home-manager.nixosModules.home-manager];

  home-manager = {
    inherit useGlobalPkgs useUserPackages backupFileExtension;
    users.${username} = import homeConfigPath;
    extraSpecialArgs =
      specialArgs
      // {
        isLinux = true;
        isNixOs = true;
        isDarwin = false;
        isWsl = false;
        hmUsername = username;
      }
      // extraSpecialArgs;
  };
}
