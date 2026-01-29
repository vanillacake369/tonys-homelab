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

    # =========================================================================
    # Exit Node MASQUERADE 규칙 (수동 NAT)
    # =========================================================================
    #
    # [왜 필요한가?]
    #   Tailscale은 기본적으로 netfilter-mode=on 에서
    #   Exit Node용 MASQUERADE 규칙을 자동으로 추가합니다.
    #   하지만 이 서버는 --netfilter-mode=nodivert 를 사용하므로
    #   Tailscale이 NAT 규칙을 자동으로 생성하지 않습니다.
    #
    # [왜 nodivert를 유지하는가?]
    #   이 서버는 복잡한 네트워크 구성을 가지고 있습니다:
    #   - vmbr0 브릿지 + VLAN 필터링 (vlan10, vlan20)
    #   - MicroVM에는 br_netfilter ON, 호스트에는 의도적으로 OFF
    #   - NixOS iptables NAT로 VLAN 간 트래픽 라우팅
    #   divert 모드는 이 모든 netfilter 규칙을 우회하여
    #   VLAN 격리, NAT, 방화벽이 무력화될 수 있습니다.
    #
    # [이 규칙이 하는 일]
    #   Tailscale 네트워크(100.64.0.0/10)에서 들어온 트래픽이
    #   외부 인터페이스(vmbr0)로 나갈 때 소스 IP를 서버 IP로 변환합니다.
    #   이를 통해 Exit Node 클라이언트의 인터넷 트래픽이
    #   홈랩 서버를 경유하여 정상적으로 라우팅됩니다.
    #
    # [트래픽 흐름]
    #   클라이언트(공공WiFi)
    #     → Tailscale 터널 (100.64.0.0/10)
    #       → 홈랩 서버 (Exit Node)
    #         → MASQUERADE (소스 IP 변환)
    #           → vmbr0 → 인터넷
    # =========================================================================
    extraCommands = ''
      iptables -t nat -A POSTROUTING \
        -s 100.64.0.0/10 \
        -o vmbr0 \
        -j MASQUERADE \
        -m comment --comment "Tailscale Exit Node NAT (nodivert 보완)"
    '';

    # 서비스 재시작 시 중복 규칙 방지를 위한 정리
    extraStopCommands = ''
      iptables -t nat -D POSTROUTING \
        -s 100.64.0.0/10 \
        -o vmbr0 \
        -j MASQUERADE \
        -m comment --comment "Tailscale Exit Node NAT (nodivert 보완)" \
        2>/dev/null || true
    '';
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
