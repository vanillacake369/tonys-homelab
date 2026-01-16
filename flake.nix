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
    colmena,
    ...
  } @ inputs: let
    # Homelab configuration - centralized magic values
    homelabConfig = {
      username = "limjihoon";
      hostname = "homelab";
      deployment = {
        targetHost = "homelab";
        targetUser = "limjihoon";
      };
    };

    specialArgs = {
      inherit inputs homelabConfig;
      sshPublicKey = builtins.getEnv "SSH_PUB_KEY";
    };
    # 모든 호스트(물리 서버 및 VM)가 공유하는 공통 NixOS 모듈
    sharedModules = [
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
      home-manager.nixosModules.home-manager
      ./configuration.nix
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          users.${homelabConfig.username} = import ./home.nix;
          extraSpecialArgs = {
            inherit homelabConfig;
            isLinux = true;
            isDarwin = false;
            isWsl = false;
            isNixOs = true;
          };
        };
      }
    ];
    # 홈랩 서버 시스템 아키텍쳐
    system = "x86_64-linux";
    # 배포 가능한 클라이언트 시스템 아키텍쳐 목록
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  in {
    # 작업 환경(Linux/Mac)에 맞는 Colmena 패키지
    packages = nixpkgs.lib.genAttrs supportedSystems (sys: {
      inherit (colmena.packages.${sys}) colmena;
    });

    # 표준 NixOS 설정 (로컬 빌드/테스트용)
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules = sharedModules;
    };

    # Colmena Hive 설정
    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {inherit system;};
        inherit specialArgs;
      };

      # 홈랩 서버 노드 정의
      homelab = {
        deployment = {
          # .ssh/config 의 Host 별칭 사용
          targetHost = homelabConfig.deployment.targetHost;
          targetUser = homelabConfig.deployment.targetUser;
          # 서버 자원을 사용하여 빌드 (로컬 부하 감소)
          buildOnTarget = true;
          tags = ["physical" "homelab"];
        };
        imports = sharedModules;
      };

      # 미래의 MicroVM 노드 추가 시에도 sharedModules를 재사용하거나 확장하기 쉬움
    };
  };
}
