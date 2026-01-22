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
    ];

}
