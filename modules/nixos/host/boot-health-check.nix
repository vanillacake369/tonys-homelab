# Boot health check with automatic rollback for headless servers
#
# Ensures that after a new deployment, critical services (sshd, tailscale, network)
# are healthy. If the check fails 3 times in a row, automatically rolls back to the
# previous NixOS generation and reboots.
#
# Flow:
#   Boot -> sshd, tailscale start -> boot-health-check.service runs
#     -> success: mark generation as "blessed" (skip checks on subsequent boots)
#     -> failure: decrement tries counter
#       -> tries > 0: reboot and retry
#       -> tries == 0: rollback to previous generation + reboot
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.boot-health-check;
  stateDir = "/var/lib/boot-safety";
  tailscaleEnabled = config.services.tailscale.enable;
in {
  options.services.boot-health-check = {
    enable = lib.mkEnableOption "boot health check with automatic rollback";

    pingTarget = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1";
      description = "IP address to ping for network connectivity check";
    };

    maxTries = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Maximum number of boot attempts before rollback";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create state directory
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
    ];

    systemd.services.boot-health-check = {
      description = "Boot health check with automatic rollback";

      before = ["boot-complete.target"];
      requiredBy = ["boot-complete.target"];
      after =
        [
          "network-online.target"
          "sshd.service"
          "multi-user.target"
        ]
        ++ lib.optionals tailscaleEnabled ["tailscale.service"];
      wants = ["network-online.target"];

      path = [
        pkgs.coreutils
        pkgs.systemd
        pkgs.iputils
        pkgs.nix
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "180s";
      };

      script = ''
        set -euo pipefail

        STATE_DIR="${stateDir}"
        BLESSED_FILE="$STATE_DIR/blessed"
        TRIES_FILE="$STATE_DIR/tries-left"
        CURRENT_SYSTEM=$(readlink /run/current-system)
        MAX_TRIES=${toString cfg.maxTries}

        log() {
          echo "[boot-health-check] $1"
        }

        # ---------------------------------------------------------------
        # 1. Check if current generation is already blessed
        # ---------------------------------------------------------------
        if [ -f "$BLESSED_FILE" ] && [ "$(cat "$BLESSED_FILE")" = "$CURRENT_SYSTEM" ]; then
          log "Generation already blessed, skipping checks"
          exit 0
        fi

        # ---------------------------------------------------------------
        # 2. New generation detected — initialize tries counter
        # ---------------------------------------------------------------
        if [ ! -f "$TRIES_FILE" ] || [ "$(cat "$TRIES_FILE" | head -1 | cut -d: -f1)" != "$CURRENT_SYSTEM" ]; then
          log "New generation detected: $CURRENT_SYSTEM"
          echo "$CURRENT_SYSTEM:$MAX_TRIES" > "$TRIES_FILE"
        fi

        TRIES=$(cat "$TRIES_FILE" | head -1 | cut -d: -f2)
        log "Tries remaining: $TRIES"

        # ---------------------------------------------------------------
        # 3. Health checks
        # ---------------------------------------------------------------
        HEALTHY=true

        # Check sshd
        if systemctl is-active --quiet sshd.service; then
          log "OK: sshd is running"
        else
          log "FAIL: sshd is not running"
          HEALTHY=false
        fi

        # Check tailscale (only if enabled)
        ${lib.optionalString tailscaleEnabled ''
          if systemctl is-active --quiet tailscaled.service; then
            log "OK: tailscaled is running"
          else
            log "FAIL: tailscaled is not running"
            HEALTHY=false
          fi
        ''}

        # Check network connectivity
        if ping -c 1 -W 5 "${cfg.pingTarget}" >/dev/null 2>&1; then
          log "OK: network connectivity (ping ${cfg.pingTarget})"
        else
          log "FAIL: cannot reach ${cfg.pingTarget}"
          HEALTHY=false
        fi

        # ---------------------------------------------------------------
        # 4. Handle result
        # ---------------------------------------------------------------
        if [ "$HEALTHY" = "true" ]; then
          log "All checks passed — blessing generation"
          echo "$CURRENT_SYSTEM" > "$BLESSED_FILE"
          rm -f "$TRIES_FILE"
          exit 0
        fi

        # ---------------------------------------------------------------
        # 5. Health check failed — decrement tries or rollback
        # ---------------------------------------------------------------
        TRIES=$((TRIES - 1))
        log "Health check failed, tries remaining: $TRIES"

        if [ "$TRIES" -gt 0 ]; then
          echo "$CURRENT_SYSTEM:$TRIES" > "$TRIES_FILE"
          log "Rebooting to retry..."
          systemctl reboot
          exit 1
        fi

        # ---------------------------------------------------------------
        # 6. All tries exhausted — rollback to previous generation
        # ---------------------------------------------------------------
        log "All tries exhausted, initiating rollback"
        rm -f "$TRIES_FILE"

        # Find previous generation
        CURRENT_GEN=$(nix-env --list-generations --profile /nix/var/nix/profiles/system | grep current | awk '{print $1}')
        PREV_GEN=$((CURRENT_GEN - 1))

        if [ "$PREV_GEN" -lt 1 ]; then
          log "CRITICAL: No previous generation to rollback to. Manual intervention required."
          exit 1
        fi

        log "Rolling back from generation $CURRENT_GEN to $PREV_GEN"
        nix-env --switch-generation "$PREV_GEN" --profile /nix/var/nix/profiles/system
        /nix/var/nix/profiles/system/bin/switch-to-configuration boot
        log "Rollback complete, rebooting into previous generation..."
        systemctl reboot
      '';
    };
  };
}
