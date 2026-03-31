{
  description = "NixOS homelab server configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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

  outputs = {nixpkgs, ...} @ inputs: let
    inherit (nixpkgs) lib;

    # SSOT: Data layer at root
    data = {
      network = import ./data/network.nix;
      vms = import ./data/vms.nix;
      hosts = import ./data/hosts.nix;
    };

    pkgs = import nixpkgs {
      system = data.hosts.common.platform;
      config.allowUnfree = true;
    };

    baseDir = ./.;

    specialArgs = {
      inherit inputs data;
      microvmTargets = let
        env = builtins.getEnv "MICROVM_TARGETS";
      in
        if env == "" || env == "all"
        then null
        else if env == "none"
        then []
        else builtins.filter (n: n != "") (builtins.split " " env);
      sshPublicKey = builtins.getEnv "SSH_PUB_KEY";
      vmSecretsPath = "/run/host-secrets";
      microvmTarget = null;
    };

    # Core logic moved to core/
    mkMicroVMs = import ./core/mk-microvms.nix {
      inherit lib data specialArgs baseDir pkgs;
    };

    mkColmenaHive = {
      mainSystem,
      hostModules,
    }:
      import ./core/mk-colmena.nix {
        inherit lib inputs data specialArgs mainSystem hostModules baseDir;
      };

    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f: lib.genAttrs supportedSystems f;
    mainSystem = data.hosts.common.platform;

    hostModules = [
      inputs.microvm.nixosModules.host
      inputs.disko.nixosModules.disko
      ./modules/platform/host/sops.nix
      ./modules/common/system.nix
      ./configuration.nix
      mkMicroVMs
    ];
  in {
    packages = forAllSystems (sys: {
      colmena = inputs.colmena.packages.${sys}.colmena;
    });

    formatter = forAllSystems (sys: inputs.nixpkgs.legacyPackages.${sys}.alejandra);

    nixosConfigurations.homelab = lib.nixosSystem {
      system = mainSystem;
      inherit specialArgs;
      modules = hostModules;
    };

    colmenaHive = mkColmenaHive {inherit mainSystem hostModules;};
  };
}
