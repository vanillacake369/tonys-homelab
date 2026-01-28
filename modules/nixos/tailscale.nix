{
  config,
  pkgs,
  ...
}: let
  clientSecret = config.sops.secrets."tailscale/clientSecret".path;
in {
  # Tailscale 패키지 설치
  environment.systemPackages = [pkgs.tailscale];

  # Tailscale 서비스 활성화
  # Tailscale이 NixOS 방화벽을 우회(Divert)하지 못하도록 설정
  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--ssh"
      "--netfilter-mode=nodivert"
    ];
  };

  # Tailscale 인터페이스를 위한 방화벽 설정 (필요한 경우)
  networking.firewall = {
    # Tailscale의 기본 포트 허용
    allowedUDPPorts = [config.services.tailscale.port];

    # Tailscale 인터페이스(tailscale0)에서의 트래픽은 모두 허용하도록 설정하는 것이 일반적입니다.
    trustedInterfaces = ["tailscale0"];
  };

  # sops-nix를 통한 자동 로그인 구현
  # OAuth client secret을 auth key로 직접 사용
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    after = ["network-online.target" "tailscale.service"];
    wants = ["network-online.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];

    path = [pkgs.tailscale pkgs.jq pkgs.coreutils];

    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    script = ''
      # 이미 로그인 상태라면 종료
      status=$(tailscale status -json | jq -r .BackendState)
      if [ "$status" = "Running" ]; then
        exit 0
      fi

      # OAuth client secret을 auth key로 사용
      SECRET=$(cat ${clientSecret})

      # 인증 실행
      tailscale up \
        --authkey="$SECRET" \
        --ssh \
        --netfilter-mode=nodivert
    '';
  };
}
