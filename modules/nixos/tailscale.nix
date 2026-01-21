{
  config,
  pkgs,
  ...
}: {
  # Tailscale 패키지 설치
  environment.systemPackages = [pkgs.tailscale];

  # Tailscale 서비스 활성화
  # Tailscale이 NixOS 방화벽을 우회(Divert)하지 못하도록 설정
  services.tailscale = {
    enable = true;
    extraSetFlags = ["--netfilter-mode=nodivert"];
  };

  # Tailscale 인터페이스를 위한 방화벽 설정 (필요한 경우)
  networking.firewall = {
    # Tailscale의 기본 포트 허용
    allowedUDPPorts = [config.services.tailscale.port];

    # Tailscale 인터페이스(tailscale0)에서의 트래픽은 모두 허용하도록 설정하는 것이 일반적입니다.
    trustedInterfaces = ["tailscale0"];
  };

  # TODO : sops-nix 를통해 자동 로그인 구현
  # 서비스가 시작된 후 자동으로 'tailscale up'을 실행하는 원샷 서비스 (선택 사항)
  # systemd.services.tailscale-autoconnect = {
  #   description = "Automatic connection to Tailscale";
  #   after = ["network-online.target" "tailscale.service"];
  #   wants = ["network-online.target" "tailscale.service"];
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig.Type = "oneshot";
  #   script = ''
  #     # 이미 로그인되어 있는지 확인 후 실행
  #     status=$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)
  #     if [ "$status" = "Running" ]; then # 이미 실행 중이면 스킵
  #       exit 0
  #     fi
  #
  #     # sops-nix를 통해 가져온 키로 로그인 (예시)
  #     # ${pkgs.tailscale}/bin/tailscale up --authkey $(cat ${config.sops.secrets.tailscale_key.path})
  #   '';
  # };
}
