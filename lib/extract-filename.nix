# 디렉토리의 *.nix 파일을 탐색하여 파일명(확장자 제외) 목록을 반환하는 함수
# 사용: discoverNodes = import ./extract-filename.nix { inherit lib; };
#       names = discoverNodes ../nodes/physical;
{lib}: dir:
lib.pipe (builtins.readDir dir) [
  # regular 파일만 필터링 (디렉토리, 심링크 제외)
  (lib.filterAttrs (_: type: type == "regular"))
  # 파일명 목록으로 변환
  builtins.attrNames
  # .nix 확장자 파일만 선택
  (lib.filter (lib.hasSuffix ".nix"))
  # 확장자 제거 → 노드 이름
  (map (lib.removeSuffix ".nix"))
]
