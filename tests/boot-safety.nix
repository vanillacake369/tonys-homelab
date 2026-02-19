# NixOS VM integration test for boot-health-check service
#
# Verifies:
#   - Service exists and starts correctly
#   - boot-complete.target dependency is wired
#   - Blessed file is created on successful health check
#   - Tries file is cleaned up after blessing
#
# Usage: nix build .#checks.x86_64-linux.boot-safety -L
{
  name = "boot-safety";

  nodes.machine = {pkgs, ...}: {
    imports = [
      ../modules/nixos/host/boot-health-check.nix
    ];

    services.boot-health-check = {
      enable = true;
      pingTarget = "127.0.0.1"; # VM network isolation
    };

    # Minimal dependencies for the test
    services.openssh.enable = true;
    # tailscale deliberately not enabled (VM isolation)
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # 1. Verify service unit exists
    machine.succeed("systemctl cat boot-health-check.service")

    # 2. Verify boot-complete.target dependency
    machine.succeed(
        "systemctl show boot-health-check.service -p Before | grep boot-complete.target"
    )

    # 3. Run the health check service
    machine.succeed("systemctl start boot-health-check.service")

    # 4. Verify blessed file is created with current system path
    machine.succeed("test -f /var/lib/boot-safety/blessed")
    current_system = machine.succeed("readlink /run/current-system").strip()
    blessed = machine.succeed("cat /var/lib/boot-safety/blessed").strip()
    assert current_system == blessed, f"Blessed mismatch: {current_system} != {blessed}"

    # 5. Verify tries file is cleaned up after successful blessing
    machine.succeed("test ! -f /var/lib/boot-safety/tries-left")

    # 6. Re-running should skip checks (already blessed)
    machine.succeed("systemctl restart boot-health-check.service")
    machine.succeed(
        "journalctl -u boot-health-check.service --no-pager | grep 'already blessed'"
    )
  '';
}
