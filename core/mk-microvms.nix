# Simplified MicroVM Registry
#
# 이 파일은 더 이상 개별 VM의 상세 설정을 관리하지 않습니다.
# 대신 vms/ 폴더에 있는 각 VM 설정 파일을 로드하여 MicroVM으로 등록하는 역할만 수행합니다.
{
  lib,
  data,
  specialArgs,
  baseDir,
  ...
}: _: let
  # 전체 VM 타겟 목록 (lib/data/vms.nix 정의 기반)
  allTargets = builtins.attrNames data.vms.definitions;

  # 빌드 대상 필터링 (MICROVM_TARGETS 환경변수 처리)
  vms =
    if specialArgs.microvmTargets == null
    then allTargets
    else builtins.filter (name: builtins.elem name specialArgs.microvmTargets) allTargets;

  # VM 이름 → 설정 파일 경로 매핑
  vmConfigPath = name: baseDir + "/vms/${name}.nix";
in {
  config = {
    # MicroVM 호스트 기능 활성화
    microvm.host.enable = true;

    # 선택된 MicroVM 목록 생성 및 등록
    microvm.vms =
      if specialArgs.microvmTargets == []
      then {}
      else
        lib.genAttrs vms (name: {
          config = {
            imports = [
              (vmConfigPath name)
            ];
          };
          # 각 VM에 자신의 이름을 microvmTarget으로 전달 (vm-base.nix 등에서 사용)
          specialArgs = specialArgs // {microvmTarget = name;};
          autostart = true;
        });
  };
}
