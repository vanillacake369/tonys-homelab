{
  inputs,
  homelabConfig,
  lib,
  ...
}: let
  userName = homelabConfig.username;
in {
  imports = [inputs.sops-nix.nixosModules.sops];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    # 정적 시크릿 -> k8s, tailscale
    # 동적 시크릿 -> users
    # INFO : k8s 서비스가 읽을 수 있도록 044 권한 부여
    secrets =
      {
        "k8s/joinToken" = {
          mode = "0444";
        };
        "tailscale/clientSecret" = {};
        # Root password for all systems
        "rootPassword" = {
          key = "users/rootPassword";
          neededForUsers = true;
        };
      }
      // (lib.optionalAttrs (userName != "root") {
        "${userName}Password" = {
          key = "users/${userName}Password";
          neededForUsers = true;
        };
      });
  };
}
