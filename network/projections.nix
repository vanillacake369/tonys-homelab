{topology ? import ./topology.nix}: {
  # Derived topology views live here so topology.nix can stay a shallow fact log.
  vmsForHost = hostName:
    builtins.listToAttrs (
      map
      (
        name: {
          inherit name;
          value = topology.vms.${name};
        }
      )
      (
        builtins.filter (name: topology.vms.${name}.parentHost == hostName)
        (builtins.attrNames topology.vms)
      )
    );
}
