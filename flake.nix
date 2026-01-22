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

    # 아키텍처 및 시스템 설정
    mainSystem = "x86_64-linux";
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f: lib.genAttrs supportedSystems f;

    # 공통 인자 및 상수
    # NOTE : sshPublicKey 는 외부에서 주입되는 값
    # flake 외부 환경변수는 --impure 실행 시에만 유효함
    homelabConstants = import ./lib/homelab-constants.nix;
    specialArgs = {
      inherit inputs homelabConstants;
      homelabConfig = homelabConstants.host;
      sshPublicKey = let
        envKey = builtins.getEnv "SSH_PUB_KEY";
      in
        if envKey != ""
        then envKey
        else "";
      isCI = false;
    };

    # MicroVM 생성기 (DRY - Don't Repeat Yourself)
    mkMicroVMs = hostConfig: let
      vms = [];
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

    # 호스트 공통 모듈 (NixOS & Colmena 공통)
    hostModules = [
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      inputs.microvm.nixosModules.host
      inputs.home-manager.nixosModules.home-manager
      ./configuration.nix
      ({config, isCI, ...}: {
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
        # 호스트는 부트스트랩용 최소 VM만 관리
        microvm.host.enable = true;
        microvm.vms =
          if isCI
          then {}
          else mkMicroVMs config;
      })
    ];

    # VM 공통 모듈 (Colmena 노드용)
    # sops는 VM의 SSH host key를 복호화 키로 사용
    vmModules = [
      inputs.microvm.nixosModules.microvm
      ./modules/nixos/sops.nix
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
      modules = hostModules;
    };

    # CI용 (MicroVM 제외)
    nixosConfigurations.homelabCi = lib.nixosSystem {
      system = mainSystem;
      specialArgs = specialArgs // {isCI = true;};
      modules = hostModules;
    };

    # 원격 배포용 (colmena)
    # TODO : 홈랩용 Colmena, 각 VM 용 Colmena 를 분리해야함
    # TODO : ./justfile 의 deploy 는 전체 배포로 남겨두되
    # 분리한 Colmena 별로 deploy 를 따로 구성하여
    # fractional changes 에 대해서 배포가능하게끔 수정해야함
    colmenaHive = let
      baseHive = {
        meta = {
          nixpkgs = import nixpkgs {system = mainSystem;};
          inherit specialArgs;
        };
        homelab = {
          deployment = with homelabConstants.host.deployment; {
            inherit targetHost targetUser;
            buildOnTarget = true;
            tags = ["physical" "homelab" "host"];
          };
          imports = hostModules;
        };
      };
      vmHive = lib.mapAttrs (name: vmInfo: {
        deployment = {
          targetHost = vmInfo.ip;
          targetUser = vmInfo.deployment.user;
          tags = vmInfo.deployment.tags;
        };
        imports = vmModules ++ [
          ./vms/${name}.nix
          ({...}: {
            users.users.${vmInfo.deployment.user}.openssh.authorizedKeys.keys =
              lib.optional (specialArgs.sshPublicKey != "") specialArgs.sshPublicKey;

            services.openssh.hostKeys = [
              {
                path = "/etc/ssh/ssh_host_ed25519_key";
                type = "ed25519";
              }
            ];
          })
        ];
      }) (lib.filterAttrs (_: vmInfo: vmInfo.deployment.colmena or true) homelabConstants.vms);
    in
      inputs.colmena.lib.makeHive (baseHive // vmHive);

    # 외부에서 상수를 참조할 수 있도록 노출
    inherit homelabConstants;
  };
}
