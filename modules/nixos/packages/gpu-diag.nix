# GPU 진단 패키지
# OpenGL, Vulkan 진단 도구
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    mesa-demos # glxinfo, glxgears
    vulkan-tools # vulkaninfo
  ];
}
