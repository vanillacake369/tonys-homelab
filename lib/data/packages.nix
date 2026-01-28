# 카테고리별 패키지명 리스트
{
  core = ["coreutils" "findutils" "gnugrep" "gnused"];
  shell = ["bat" "ripgrep" "fzf" "jq" "tree"];
  editor = ["neovim" "vim"];
  network = ["curl" "wget" "bind" "tcpdump" "nftables"];
  monitoring = ["htop" "btop" "ncdu" "lsof" "psmisc"];
  dev = ["git" "strace" "moreutils" "expect"];
  k8s = ["kubectl"];
  hardware = ["pciutils" "usbutils" "dmidecode"];
  gpu-amd = ["amdgpu_top"];
  virtualization = ["bridge-utils"];
  terminal = ["zellij" "screen"];
  misc = ["neofetch" "ngrok"];
  gpu-diag = ["mesa-demos" "vulkan-tools"];
}
