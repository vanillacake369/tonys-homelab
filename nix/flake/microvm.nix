{
  lib,
  homelabConstants,
  specialArgs,
}: {
  mkMicroVMs = hostConfig: let
    allTargets = builtins.attrNames homelabConstants.vms;
    vms =
      if specialArgs.microvmTargets == null
      then allTargets
      else builtins.filter (name: builtins.elem name specialArgs.microvmTargets) allTargets;
    vmSpecialArgs =
      specialArgs
      // {
        hostSshKeys = hostConfig.users.users.${homelabConstants.host.username}.openssh.authorizedKeys.keys;
      };
  in
    lib.genAttrs vms (name: {
      config = ./../../vms/${name}.nix;
      specialArgs = vmSpecialArgs // {microvmTarget = name;};
      autostart = true;
    });
}
