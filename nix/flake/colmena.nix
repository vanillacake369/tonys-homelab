{
  inputs,
  lib,
  homelabConstants,
  specialArgs,
  hostModules,
  vmModules,
  mainSystem,
}: let
  baseHive = {
    meta = {
      nixpkgs = import inputs.nixpkgs {system = mainSystem;};
      inherit specialArgs;
    };
    homelab = {
      deployment = with homelabConstants.host.deployment; {
        inherit targetHost targetUser;
        buildOnTarget = true;
        tags = ["physical" "homelab"];
      };
      imports = hostModules;
    };
  };
  vmHive = lib.mapAttrs (name: vmInfo: {
    deployment = {
      targetHost = vmInfo.ip;
      targetUser = vmInfo.deployment.user;
      buildOnTarget = true;
      tags = vmInfo.deployment.tags;
    };
    imports =
      vmModules
      ++ [
        ./../../vms/${name}.nix
        (
          _: {
            users.users.${vmInfo.deployment.user}.openssh.authorizedKeys.keys =
              lib.optional (specialArgs.sshPublicKey != "") specialArgs.sshPublicKey;

            services.openssh.hostKeys = [
              {
                path = "/etc/ssh/ssh_host_ed25519_key";
                type = "ed25519";
              }
            ];
          }
        )
      ];
  }) (lib.filterAttrs (_: vmInfo: vmInfo.deployment.colmena or true) homelabConstants.vms);
in
  inputs.colmena.lib.makeHive (baseHive // vmHive)
