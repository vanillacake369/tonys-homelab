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

    # 1. 아키텍처 및 시스템 설정
    mainSystem = "x86_64-linux";
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f: lib.genAttrs supportedSystems f;

    # 2. CI 환경 감지 및 상수 로드
    isCI = builtins.getEnv "CI" == "true";
    homelabConstants = import (
      if isCI || !(builtins.pathExists ./lib/homelab-constants.nix)
      then ./lib/homelab-constants-example.nix
      else ./lib/homelab-constants.nix
    );

    # 3. 공통 아규먼트 (SpecialArgs)
    specialArgs = {
      inherit inputs homelabConstants;
      homelabConfig = homelabConstants.host;
      # Flake 외부 환경변수는 --impure 실행 시에만 유효함
      sshPublicKey = builtins.getEnv "SSH_PUB_KEY";
    };

    # 4. MicroVM 생성기 (DRY - Don't Repeat Yourself)
    mkMicroVMs = hostConfig: let
      vms = ["vault" "jenkins" "registry" "k8s-master" "k8s-worker-1" "k8s-worker-2"];
      vmSpecialArgs =
        specialArgs
        // {
          hostSshKeys = hostConfig.users.users.${homelabConstants.host.username}.openssh.authorizedKeys.keys;
        };
    in
      lib.genAttrs vms (name: {
        config = ./vms/${name}.nix;
        specialArgs = vmSpecialArgs;
        autostart = true;
      });

    # 5. 공유 모듈 (NixOS & Colmena 공통)
    sharedModules = [
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      inputs.microvm.nixosModules.host
      inputs.home-manager.nixosModules.home-manager
      ./configuration.nix
      ({config, ...}: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          users.${homelabConstants.host.username} = import ./home.nix;
          extraSpecialArgs =
            specialArgs
            // {
              isLinux = true;
              isNixOs = true;
              isDarwin = false;
              isWsl = false;
            };
        };

        # CI 환경에서는 빌드 부하를 줄이기 위해 MicroVM 정의를 비움
        microvm.host.enable = true;
        microvm.vms =
          if isCI
          then {}
          else mkMicroVMs config;
      })
    ];
  in {
    # 모든 지원 아키텍처에서 colmena 패키지 사용 가능
    packages = forAllSystems (sys: {
      inherit (inputs.colmena.packages.${sys}) colmena;
    });

    # 로컬 빌드용 (nixos-rebuild)
    nixosConfigurations.homelab = lib.nixosSystem {
      system = mainSystem;
      inherit specialArgs;
      modules = sharedModules;
    };

    # 원격 배포용 (colmena)
    colmenaHive = inputs.colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {system = mainSystem;};
        inherit specialArgs;
      };
      homelab = {
        deployment = with homelabConstants.host.deployment; {
          inherit targetHost targetUser;
          buildOnTarget = true;
          tags = ["physical" "homelab"];
        };
        imports = sharedModules;
      };
    };

    # 외부에서 상수를 참조할 수 있도록 노출
    inherit homelabConstants;
  };
}
