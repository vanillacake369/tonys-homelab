{
  inputs,
  homelabConstants,
  specialArgs,
  mkMicroVMs,
}: {
  hostModules = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.microvm.nixosModules.host
    inputs.home-manager.nixosModules.home-manager
    ./../../configuration.nix
    ({
      config,
      isCI,
      ...
    }: {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        users.${homelabConstants.host.username} = import ./../../home.nix;
        extraSpecialArgs =
          specialArgs
          // {
            isLinux = true;
            isNixOs = true;
            isDarwin = false;
            isWsl = false;
          };
      };

      microvm.host.enable = true;
      microvm.vms =
        if isCI
        then {}
        else mkMicroVMs config;
    })
  ];

  vmModules = [
    inputs.microvm.nixosModules.microvm
    ./../../modules/nixos/sops.nix
    {
      nixpkgs.config.allowUnfree = true;
    }
  ];
}
