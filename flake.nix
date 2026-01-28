{
  description = "NixOS homelab server configuration";

  inputs = {
    # Nixpkgs 채널 (unstable 기반)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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

    # Pure data layer: 단일 데이터 소스
    data = {
      packages = import ./lib/data/packages.nix;
      network = import ./lib/data/network.nix;
      vms = import ./lib/data/vms.nix;
      hosts = import ./lib/data/hosts.nix;
    };

    pkgs = import nixpkgs {
      system = data.hosts.common.platform;
      config.allowUnfree = true;
    };

    # 레포지토리 루트 경로
    baseDir = ./.;

    # specialArgs: data + env + inputs만 전달
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
      microvmTarget = null; # 호스트용 기본값 (VM은 mk-microvms.nix에서 override)
    };

    # MicroVM 구성 모듈 생성기
    mkMicroVMs = import ./lib/mk-microvms.nix {
      inherit lib data specialArgs baseDir pkgs;
    };

    # Colmena 하이브 생성기
    mkColmenaHive = {
      mainSystem,
      hostModules,
    }:
      import ./lib/mk-colmena.nix {
        inherit lib inputs data specialArgs mainSystem hostModules baseDir;
      };

    # 지원 플랫폼 목록
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

    # 시스템별 패키지 생성 헬퍼
    forAllSystems = f: lib.genAttrs supportedSystems f;

    # 메인 배포 대상 시스템
    mainSystem = data.hosts.common.platform;

    # 호스트 모듈 묶음
    hostModules = [
      inputs.microvm.nixosModules.host
      inputs.disko.nixosModules.disko
      ./modules/nixos/sops.nix
      ./configuration.nix
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
    colmenaHive = mkColmenaHive {inherit mainSystem hostModules;};
  };
}
