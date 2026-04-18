{
  description = "Tony's Homelab - Atomic NixOS Architecture";

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

  # 의존성 주입
  outputs = {nixpkgs, ...} @ inputs: let
    # nixpkgs의 lib 유틸리티 사용
    inherit (nixpkgs) lib;

    # 지원 Architecture 목록
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

    # Architecture 별 패키지 생성 헬퍼
    forAllSystems = f: lib.genAttrs supportedSystems f;
    packages = forAllSystems (sys: {
      inherit (inputs.colmena.packages.${sys}) colmena;
    });

    # Host 구성 헬퍼함수인 mk-host
    mkHost = import ./lib/mk-host.nix {inherit lib inputs;};

    # VM 구성 헬퍼함수인 mk-vms
    mkVMs = import ./lib/mk-vms.nix {inherit lib inputs;};

    # Host 구성 헬퍼함수인 mk-colmena
    hive = import ./lib/mk-colmena.nix {
      inherit lib inputs mkHost mkVMs;
    };
  in {
    inherit packages;

    # 헬퍼함수를 통해
    # Host & VM 에 대한
    # Colmena 하이브 선언
    # NOTE:
    # 로컬 배포 & 운영 배포 모두 지원
    # - 로컬 배포 (서버에서 빌드 & 실행)
    #   - colmena build --on @{{ target }}
    #   - nixos-rebuild switch ./result/{{ target }}
    # - 운영 배포 (원격 실행)
    #   - nix run --impure .#colmena -- apply --on @{{ target }}
    # - 테스트/확인
    #   - nix run --impure .#colmena -- apply --dry-run --on @{{ target }}
    colmenaHive = hive;
  };
}
