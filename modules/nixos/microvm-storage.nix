# MicroVM storage directory management
# Automatically creates required storage directories for all VMs
{
  lib,
  pkgs,
  homelabConstants,
  ...
}: let
  # Extract all VM storage paths from constants
  vmStoragePaths =
    lib.mapAttrsToList (
      _: vm:
        if vm ? storage && vm.storage ? source
        then vm.storage.source
        else null
    )
    homelabConstants.vms;

  # Filter out nulls and get unique paths
  storageDirs = lib.filter (path: path != null) vmStoragePaths;
in {
  # Create storage directories using systemd-tmpfiles
  systemd.tmpfiles.rules =
    map (path: "d ${path} 0755 microvm kvm - -") storageDirs
    ++ [
      # Ensure base directories exist
      "d /var/lib/microvms 0755 microvm kvm - -"
      "d /var/lib/microvms/iso 0755 microvm kvm - -"
      "d /var/lib/microvms/opnsense 0755 microvm kvm - -"
    ];

  systemd.services.install-opnsense-iso =
    let
      opnsense = homelabConstants.vms.opnsense;
      isoPath = opnsense.storage.iso;
      isoDir = builtins.dirOf isoPath;
    in {
      description = "Download OPNsense ISO";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "systemd-tmpfiles-setup.service"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        if [ -f "${isoPath}" ]; then
          exit 0
        fi
        mkdir -p "${isoDir}"
        curl -L --fail --output "${isoPath}" "${opnsense.storage.isoUrl}"
      '';
    };

  systemd.services.install-opnsense-disk =
    let
      opnsense = homelabConstants.vms.opnsense;
      diskPath = opnsense.storage.image;
      diskDir = builtins.dirOf diskPath;
    in {
      description = "Create OPNsense disk image";
      wantedBy = ["multi-user.target"];
      after = ["install-opnsense-iso.service" "systemd-tmpfiles-setup.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        if [ -f "${diskPath}" ]; then
          exit 0
        fi
        mkdir -p "${diskDir}"
        ${lib.getExe' pkgs.qemu "qemu-img"} create -f raw "${diskPath}" 20G
      '';
    };

  systemd.services."microvm@opnsense" = {
    requires = ["install-opnsense-iso.service" "install-opnsense-disk.service"];
    after = ["install-opnsense-iso.service" "install-opnsense-disk.service"];
  };
}
