# Data Layer Aggregator
# Imports all pure data files for external consumption (justfile, scripts)
{
  network = import ./network.nix;
  vms = import ./vms.nix;
  hosts = import ./hosts.nix;
}
