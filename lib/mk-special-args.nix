# specialArgs 생성 함수
# 환경변수 기반 값을 모듈 인자로 변환
{
  inputs,
  homelabConstants,
}: let
  # SSH 공개키 환경변수 처리
  sshPublicKey = let
    envKey = builtins.getEnv "SSH_PUB_KEY";
  in
    if envKey != ""
    then envKey
    else "";

  # MicroVM 대상 필터링 환경변수 처리
  microvmTargets = let
    envTargets = builtins.getEnv "MICROVM_TARGETS";
  in
    if envTargets == "" || envTargets == "all"
    then null
    else if envTargets == "none"
    then []
    else builtins.filter (name: name != "") (builtins.split " " envTargets);

  # VM에서 호스트 secrets에 접근하는 경로
  vmSecretsPath = "/run/host-secrets";
in {
  inherit inputs homelabConstants microvmTargets sshPublicKey vmSecretsPath;
  # 호스트 설정 별칭 (기존 모듈 호환성)
  homelabConfig = homelabConstants.host;
}
