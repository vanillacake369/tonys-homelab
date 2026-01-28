# 호스트 전용 패키지
{
  pkgs,
  data,
  ...
}: let
  groups = ["core" "shell" "editor" "network" "monitoring" "dev" "k8s" "hardware" "gpu-amd" "virtualization" "terminal" "misc" "gpu-diag"];
  resolve = builtins.concatLists (
    map (g: map (name: pkgs.${name}) (data.packages.${g} or []))
      groups
  );
in {
  environment.systemPackages = resolve;
}
