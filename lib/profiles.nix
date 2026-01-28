# Profiles Module
# Provides easy access to domain-based configurations
# Usage: profiles = import ./lib/profiles.nix { inherit pkgs; };
#        profiles.nixos.server.all  # NixOS server config
#        profiles.homeManager.dev.all  # home-manager dev config
{ pkgs, lib ? pkgs.lib }:
let
  # Import all domains
  domains = {
    shell = import ./domains/shell.nix;
    packages = import ./domains/packages.nix;
    editor = import ./domains/editor.nix;
    users = import ./domains/users.nix;
    network = import ./domains/network.nix;
    vms = import ./domains/vms.nix;
    hosts = import ./domains/hosts.nix;
  };

  # Create adapter for a specific profile
  mkNixosAdapter = profile: import ./adapters/nixos.nix {
    inherit domains pkgs lib profile;
  };

  mkHomeManagerAdapter = profile: import ./adapters/home-manager.nix {
    inherit domains pkgs lib profile;
  };

  # Available profile names from packages domain
  profileNames = builtins.attrNames domains.packages.profiles;
in {
  # Direct domain access (for custom configurations)
  inherit domains;

  # NixOS adapters by profile
  # Usage: profiles.nixos.server.all
  nixos = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = mkNixosAdapter name;
    }) profileNames
  );

  # Home-manager adapters by profile
  # Usage: profiles.homeManager.dev.all
  homeManager = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = mkHomeManagerAdapter name;
    }) profileNames
  );

  # Convenience: create NixOS config for a profile
  # Usage: profiles.mkNixosConfig "server"
  mkNixosConfig = profile: (mkNixosAdapter profile).all;

  # Convenience: create home-manager config for a profile
  # Usage: profiles.mkHomeManagerConfig "dev"
  mkHomeManagerConfig = profile: (mkHomeManagerAdapter profile).all;

  # Infrastructure data (network, vms, hosts)
  infrastructure = {
    network = domains.network;
    vms = domains.vms;
    hosts = domains.hosts;
  };

  # User data
  users = domains.users;
}
