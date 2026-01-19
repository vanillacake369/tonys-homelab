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
  } @ inputs: let
    # 상수 및 기본 설정
    system = "x86_64-linux";
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    homelabConstants = import ./lib/homelab-constants.nix;

    # 공통 아규먼트 (SpecialArgs)
    specialArgs = {
      inherit inputs homelabConstants;
      homelabConfig = homelabConstants.host;
      sshPublicKey = builtins.getEnv "SSH_PUB_KEY";
    };

    # MicroVM 정의 (중복 제거를 위해 함수화)
    mkMicroVMs = config: let
      vmSpecialArgs =
        specialArgs
        // {
          hostSshKeys = config.users.users.${homelabConstants.host.username}.openssh.authorizedKeys.keys;
        };
      mkVM = path: {
        config = path;
        specialArgs = vmSpecialArgs;
        autostart = true;
      };
    in {
      vault = mkVM ./vms/vault.nix;
      jenkins = mkVM ./vms/jenkins.nix;
      registry = mkVM ./vms/registry.nix;
      k8s-master = mkVM ./vms/k8s-master.nix;
      k8s-worker-1 = mkVM ./vms/k8s-worker-1.nix;
      k8s-worker-2 = mkVM ./vms/k8s-worker-2.nix;
    };

    # 공통 모듈 구성
    sharedModules = [
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
      microvm.nixosModules.host
      home-manager.nixosModules.home-manager
      ./configuration.nix
      {
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
      }
      # INFO : CI 에서는 microvm build 하지 않음
      # MicroVM 호스트 설정 통합
      ({config, ...}: let
        isCI = builtins.getEnv "CI" == "true";
      in {
        microvm.host.enable = true;
        microvm.vms =
          if isCI
          then {}
          else mkMicroVMs config;
      })
    ];
  in {
    # CLI 접근을 위한 상수 노출
    inherit homelabConstants;

    # 아키텍처별 패키지 (Colmena 등)
    packages = nixpkgs.lib.genAttrs supportedSystems (sys: {
      inherit (colmena.packages.${sys}) colmena;
    });

    # 로컬 빌드용 설정
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules = sharedModules;
    };

    # Colmena 배포 설정
    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {inherit system;};
        inherit specialArgs;
      };
      homelab = {
        deployment = {
          targetHost = homelabConstants.host.deployment.targetHost;
          targetUser = homelabConstants.host.deployment.targetUser;
          buildOnTarget = true;
          tags = ["physical" "homelab"];
        };
        imports = sharedModules;
      };
    };
  };
}
