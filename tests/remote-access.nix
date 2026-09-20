{
  assert',
  homelabConfig,
  topLevelSecretPublicKeys,
  hostLoginKeys,
  mobileHomelabKeys,
  hostIdentityKeys,
}: [
  (assert' "remote-access: users are declarative" (!homelabConfig.users.mutableUsers))
  (assert' "remote-access: SSH public keys use namespaced secrets directories" (topLevelSecretPublicKeys == []))
  (assert' "remote-access: root password comes from sops" (homelabConfig.users.users.root.hashedPasswordFile == homelabConfig.sops.secrets."users/rootPassword".path))
  (assert' "remote-access: homelab deployment user remains limjihoon" (homelabConfig.node.user == "limjihoon"))
  (assert' "remote-access: deployment user keeps passwordless sudo for Colmena" (!homelabConfig.security.sudo.wheelNeedsPassword))
  (assert' "remote-access: remote user is not declared" (!(homelabConfig.users.users ? remote)))
  (assert' "remote-access: host-owned login keys are assigned to root" (builtins.all (key: builtins.elem key homelabConfig.users.users.root.openssh.authorizedKeys.keys) hostLoginKeys))
  (assert' "remote-access: host-owned login keys are assigned to deployment user" (builtins.all (key: builtins.elem key homelabConfig.users.users.limjihoon.openssh.authorizedKeys.keys) hostLoginKeys))
  (assert' "remote-access: mobile homelab keys are assigned to limjihoon" (builtins.all (key: builtins.elem key homelabConfig.users.users.limjihoon.openssh.authorizedKeys.keys) mobileHomelabKeys))
  (assert' "remote-access: mobile homelab keys are not assigned to root" (builtins.all (key: !(builtins.elem key homelabConfig.users.users.root.openssh.authorizedKeys.keys)) mobileHomelabKeys))
  (assert' "remote-access: host identity keys are not login keys for root" (builtins.all (key: !(builtins.elem key homelabConfig.users.users.root.openssh.authorizedKeys.keys)) hostIdentityKeys))
  (assert' "remote-access: host identity keys are not login keys for deployment user" (builtins.all (key: !(builtins.elem key homelabConfig.users.users.limjihoon.openssh.authorizedKeys.keys)) hostIdentityKeys))
  (assert' "remote-access: tailscale remains enabled" homelabConfig.services.tailscale.enable)
  (assert' "remote-access: tailscale ssh is advertised on existing nodes" (builtins.elem "--ssh" homelabConfig.services.tailscale.extraSetFlags))
  (assert' "remote-access: tailscale ssh is advertised after reauth" (builtins.elem "--ssh" homelabConfig.services.tailscale.extraUpFlags))
]
