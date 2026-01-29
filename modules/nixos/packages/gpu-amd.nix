# AMD GPU 모니터링 패키지
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    amdgpu_top
  ];
}
