{
  config,
  pkgs,
  ...
}: let
  clientSecret = config.sops.secrets."tailscale/clientSecret".path;
in {
  # Exit Node를 위한 IPv6 포워딩 활성화
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

  # Tailscale 패키지 설치
  environment.systemPackages = [pkgs.tailscale];

  # Tailscale 서비스 활성화
  # Tailscale이 NixOS 방화벽을 우회(Divert)하지 못하도록 설정
  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--ssh"
      "--netfilter-mode=nodivert"
      "--advertise-exit-node"
    ];
  };

  # Tailscale 인터페이스를 위한 방화벽 설정
  networking.firewall = {
    allowedUDPPorts = [config.services.tailscale.port];
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
      RestartSec = "10s";
      # 최대 5번 재시도 후 중단 (10초 간격)
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };

    script = ''
      set -euo pipefail

      log() {
        echo "[tailscale-autoconnect] $1"
      }

      # tailscale 데몬이 준비될 때까지 대기
      for i in $(seq 1 30); do
        if tailscale status &>/dev/null; then
          break
        fi
        log "Waiting for tailscale daemon... ($i/30)"
        sleep 1
      done

      # 현재 상태 확인
      if ! status_json=$(tailscale status -json 2>&1); then
        log "ERROR: Failed to get tailscale status: $status_json"
        exit 1
      fi

      backend_state=$(echo "$status_json" | jq -r '.BackendState // "Unknown"')
      log "Current state: $backend_state"

      # 이미 연결된 경우 종료
      if [ "$backend_state" = "Running" ]; then
        log "Already connected to Tailscale"
        exit 0
      fi

      # Secret 파일 확인
      if [ ! -f "${clientSecret}" ]; then
        log "ERROR: Secret file not found: ${clientSecret}"
        exit 1
      fi

      SECRET=$(cat "${clientSecret}")
      if [ -z "$SECRET" ]; then
        log "ERROR: Secret is empty"
        exit 1
      fi

      # 인증 실행
      log "Connecting to Tailscale..."
      if ! tailscale up --authkey="$SECRET" --ssh --netfilter-mode=nodivert --advertise-exit-node 2>&1; then
        log "ERROR: Failed to connect to Tailscale"
        exit 1
      fi

      log "Successfully connected to Tailscale"
    '';
  };
}
