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

    # Domain-driven architecture: pure data from domains
    domains = {
      shell = import ./lib/domains/shell.nix;
      packages = import ./lib/domains/packages.nix;
      editor = import ./lib/domains/editor.nix;
      users = import ./lib/domains/users.nix;
      network = import ./lib/domains/network.nix;
      vms = import ./lib/domains/vms.nix;
      hosts = import ./lib/domains/hosts.nix;
    };

    # Backward compatibility: expose as homelabConstants
    homelabConstants = {
      networks = domains.network;
      vms = domains.vms.definitions;
      vmOrder = domains.vms.order;
      microvmList = domains.vms.microvmList;
      vmTagList = domains.vms.tagList;
      k8s = domains.vms.k8s;
      hosts = domains.hosts.definitions;
      defaultHost = domains.hosts.default;
      common = domains.hosts.common;
    };

    pkgs = import nixpkgs {
      system = homelabConstants.common.platform;
      config.allowUnfree = true;
    };

    # Profiles: easy access to domain-based configurations
    profiles = import ./lib/profiles.nix { inherit pkgs lib; };

    # 레포지토리 루트 경로
    baseDir = ./.;

    # 모듈에서 사용할 추가 인자 구성
    specialArgs = import ./lib/mk-special-args.nix {inherit inputs homelabConstants;} // {
      inherit domains profiles;
    };

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
    mainSystem = homelabConstants.common.platform;

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

    # NixOS 구성
    # - VM 빌드 제어: MICROVM_TARGETS 환경변수 사용
    #   - "all" 또는 미설정: 모든 VM 빌드
    #   - "none": VM 빌드 스킵 (CI용)
    #   - "vm1 vm2": 특정 VM만 빌드
    # 예: MICROVM_TARGETS=none nix build .#nixosConfigurations.homelab.config.system.build.toplevel
    nixosConfigurations.homelab = lib.nixosSystem {
      system = mainSystem;
      inherit specialArgs;
      modules = hostModules;
    };

    # 원격 배포용 Colmena 하이브
    # colmena CLI는 'colmena' 또는 'colmenaHive' output을 찾음
    colmenaHive = mkColmenaHive {inherit mainSystem hostModules;};

    # 외부 참조용 상수 노출 (justfile 호환)
    # warning: unknown flake output 'homelabConstants' 는 무해함
    inherit homelabConstants;
  };
}
