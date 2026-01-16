{
  description = "NixOS homelab server configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    disko,
    sops-nix,
    microvm,
    colmena,
    ...
  } @ inputs: {
    # Colmena package from flake input (ensures version compatibility)
    packages.x86_64-darwin.colmena = colmena.packages.x86_64-darwin.colmena;
    packages.aarch64-darwin.colmena = colmena.packages.aarch64-darwin.colmena;
    packages.x86_64-linux.colmena = colmena.packages.x86_64-linux.colmena;
    packages.aarch64-linux.colmena = colmena.packages.aarch64-linux.colmena;

    nixosConfigurations = {
      homelab = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          sshPublicKey = builtins.getEnv "SSH_PUB_KEY";
        };
        modules = [
          disko.nixosModules.disko
          ./configuration.nix
          sops-nix.nixosModules.sops

          # Integrate home-manager as NixOS module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.limjihoon = import ./home.nix;
            home-manager.extraSpecialArgs = {
              isLinux = true;
              isDarwin = false;
              isWsl = false;
              isNixOs = true;
            };
          }
        ];
      };
    };

    # Colmena hive configuration
    # See: https://colmena.cli.rs/unstable/tutorial/flakes.html
    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [];
        };
        specialArgs = {
          inherit inputs;
          # SSH public key: Read from file for Colmena deployments
          # Passwords are managed by SOPS, but public keys can be in plaintext
          sshPublicKey = builtins.readFile ./secrets/ssh-public-key.txt;
        };
      };

      # Physical homelab server
      homelab = {
        deployment = {
          targetHost = "homelab";  # Uses ~/.ssh/config
          targetUser = "limjihoon";
          buildOnTarget = true;
          tags = ["physical" "homelab"];
        };

        imports = [
          disko.nixosModules.disko
          ./configuration.nix
          sops-nix.nixosModules.sops

          # Integrate home-manager
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.limjihoon = import ./home.nix;
            home-manager.extraSpecialArgs = {
              isLinux = true;
              isDarwin = false;
              isWsl = false;
              isNixOs = true;
            };
          }
        ];
      };

      # Future: MicroVM nodes will be added here
      # Example:
      # vm-node-1 = { ... };
      # vm-node-2 = { ... };
    };
  };
}
