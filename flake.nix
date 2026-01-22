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

  outputs = {nixpkgs, ...} @ inputs: let
    inherit (nixpkgs) lib;

    homelabConstants = import ./lib/homelab-constants.nix;
    systems = import ./nix/flake/systems.nix {inherit lib;};
    specialArgs = import ./nix/flake/special-args.nix {inherit inputs homelabConstants;};
    microvm = import ./nix/flake/microvm.nix {inherit lib homelabConstants specialArgs;};
    modules = import ./nix/flake/modules.nix {
      inherit inputs homelabConstants specialArgs;
      inherit (microvm) mkMicroVMs;
    };
    colmenaHive = import ./nix/flake/colmena.nix {
      inherit inputs lib homelabConstants specialArgs;
      inherit (modules) hostModules vmModules;
      inherit (systems) mainSystem;
    };
  in {
    # 모든 지원 아키텍처에서 colmena 패키지 사용 가능
    packages = systems.forAllSystems (sys: {
      inherit (inputs.colmena.packages.${sys}) colmena;
    });

    formatter = systems.forAllSystems (sys: inputs.nixpkgs.legacyPackages.${sys}.nixpkgs-fmt);

    # 로컬 빌드용 (nixos-rebuild)
    nixosConfigurations.homelab = lib.nixosSystem {
      system = systems.mainSystem;
      inherit specialArgs;
      modules = modules.hostModules;
    };

    # CI용 (MicroVM 제외)
    nixosConfigurations.homelabCi = lib.nixosSystem {
      system = systems.mainSystem;
      specialArgs = specialArgs // {isCI = true;};
      modules = modules.hostModules;
    };

    # 원격 배포용 (colmena)
    # TODO : 홈랩용 Colmena, 각 VM 용 Colmena 를 분리해야함
    # TODO : ./justfile 의 deploy 는 전체 배포로 남겨두되
    # 분리한 Colmena 별로 deploy 를 따로 구성하여
    # fractional changes 에 대해서 배포가능하게끔 수정해야함
    colmenaHive = colmenaHive;

    # 외부에서 상수를 참조할 수 있도록 노출
    inherit homelabConstants;
  };
}
