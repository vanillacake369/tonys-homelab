{
  description = "NixOS homelab server configuration";

  inputs = {
    # Nixpkgs 채널 (unstable 기반)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # 사용자 환경 관리 (home-manager)
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 디스크 파티셔닝 자동화 (disko)
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 시크릿 관리 (sops-nix)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MicroVM 지원 모듈
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 배포 도구 (colmena)
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    # nixpkgs의 lib 유틸리티 사용
    inherit (nixpkgs) lib;
    pkgs = import nixpkgs {
      system = homelabConstants.host.platform;
      config.allowUnfree = true;
    };

    # 레포지토리 루트 경로
    baseDir = ./.;

    # lib/ 경로의 공통 상수 로딩
    homelabConstants = import ./lib/homelab-constants.nix;

    # 모듈에서 사용할 추가 인자 구성
    specialArgs = import ./lib/mk-special-args.nix {inherit inputs homelabConstants;};

    # Home Manager 공용 모듈 생성기
    mkHomeManager = import ./lib/mk-home-manager.nix {
      inherit inputs homelabConstants specialArgs;
    };

    # MicroVM 구성 모듈 생성기
    mkMicroVMs = import ./lib/mk-microvms.nix {
      inherit lib homelabConstants specialArgs baseDir pkgs;
    };

    # Colmena 하이브 생성기
    mkColmenaHive = {
      mainSystem,
      hostModules,
    }:
      import ./lib/mk-colmena.nix {
        inherit lib inputs homelabConstants specialArgs mainSystem hostModules baseDir;
      };

    # 지원 플랫폼 목록
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

    # 시스템별 패키지 생성 헬퍼
    forAllSystems = f: lib.genAttrs supportedSystems f;

    # 메인 배포 대상 시스템
    mainSystem = homelabConstants.host.platform;

    # 호스트 모듈 묶음
    hostModules = [
      inputs.microvm.nixosModules.host
      inputs.disko.nixosModules.disko
      ./modules/nixos/sops.nix
      ./configuration.nix
      (mkHomeManager {
        homeConfigPath = ./home.nix;
      })
      mkMicroVMs
    ];
  in {
    # 시스템별 colmena 패키지 노출
    packages = forAllSystems (sys: {
      colmena = inputs.colmena.packages.${sys}.colmena;
    });

    # Nix 포매터 지정 (alejandra)
    formatter = forAllSystems (sys: inputs.nixpkgs.legacyPackages.${sys}.alejandra);

    # 로컬 빌드용 NixOS 구성 (nixos-rebuild)
    nixosConfigurations.homelab = lib.nixosSystem {
      system = mainSystem;
      inherit specialArgs;
      modules = hostModules;
    };

    # CI 빌드용 NixOS 구성 (microvmTargets = [])
    nixosConfigurations.homelabCi = lib.nixosSystem {
      system = mainSystem;
      specialArgs = specialArgs // {microvmTargets = [];};
      modules = hostModules;
    };

    # 원격 배포용 Colmena 하이브
    # colmena는 표준 flake output으로 인식됨
    colmena = mkColmenaHive {inherit mainSystem hostModules;};

    # 외부 참조용 상수 노출 (justfile 호환)
    # warning: unknown flake output 'homelabConstants' 는 무해함
    inherit homelabConstants;
  };
}
