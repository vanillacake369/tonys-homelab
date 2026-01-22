{
  config,
  pkgs,
  ...
}: let
  clientId = config.sops.secrets."tailscale/clientId".path;
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

  # sops-nix 를통해 자동 로그인 구현
  # 'tailscale up' 실행 원샷 서비스
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    after = ["network-online.target" "tailscale.service"];
    wants = ["network-online.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    script = ''
      # 이미 로그인되어 있다면 skip
      status=$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)
      if [ "$status" = "Running" ]; then
        exit 0
      fi

      # OAuth 로그인
      ID=$(cat ${clientId})
      SECRET=$(cat ${clientSecret})
      AUTH_KEY="tskey-client-$ID-$SECRET"
      ${pkgs.tailscale}/bin/tailscale up \
        --authkey="$AUTH_KEY" \
        --ssh \
        --netfilter-mode=nodivert
    '';
  };
}
