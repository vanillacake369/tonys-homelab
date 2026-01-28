# AMD GPU 설정 모듈
# ROCm 및 OpenCL 지원을 위한 호스트 GPU 구성
# Hybrid K8s Cluster에서 GPU 워크로드 (Ollama 등) 실행용
{
  pkgs,
  config,
  ...
}: {
  # ============================================================
  # AMD GPU 드라이버 설정
  # ============================================================

  # initrd에서 amdgpu 모듈 로딩 (빠른 초기화)
  hardware.amdgpu.initrd.enable = true;

  # OpenGL/Vulkan 지원
  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    # ROCm OpenCL 지원
    extraPackages = with pkgs; [
      # OpenCL ICD (Installable Client Driver)
      rocmPackages.clr.icd
      rocmPackages.clr

      # Vulkan: RADV가 기본으로 활성화됨 (amdvlk는 deprecated)

      # VA-API (비디오 가속)
      libva
    ];
  };

  # ============================================================
  # ROCm 환경
  # ============================================================

  environment.systemPackages = with pkgs; [
    # GPU 모니터링 및 관리
    rocmPackages.rocm-smi # GPU 상태 모니터링
    rocmPackages.rocminfo # GPU 정보 조회
    clinfo # OpenCL 디바이스 정보

    # 개발/디버깅 도구
    rocmPackages.rocm-runtime
    rocmPackages.hip-common

    # 진단 도구
    vulkan-tools # vulkaninfo
    libva-utils # vainfo (비디오 가속 확인)
    mesa-demos # glxinfo 등 OpenGL 정보
  ];

  # ROCm 환경 변수
  environment.variables = {
    # gfx1103 (RDNA3 iGPU) 지원 활성화
    ROC_ENABLE_PRE_VEGA = "1";
    # HSA 런타임 설정
    HSA_OVERRIDE_GFX_VERSION = "11.0.3";
  };

  # ============================================================
  # 사용자 권한 설정
  # ============================================================

  # GPU 접근을 위한 그룹 설정
  # video: 디스플레이/렌더링
  # render: GPU 컴퓨팅 (ROCm)
  users.users.limjihoon.extraGroups = ["video" "render"];
}
