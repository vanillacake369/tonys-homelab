# SSH configuration for host
{
  data,
  lib,
  ...
}: let
  vms = data.vms.definitions;
  # Generate static Host definitions from data
  mkVmHostConfigs = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: vmInfo: ''
      Host ${name} ${vmInfo.hostname}
        HostName ${vmInfo.ip}
    '')
    vms);
in {
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # SSH client configuration for host -> VM access
  programs.ssh.extraConfig = ''
        # Global VM defaults
        Host 10.0.* k8s-master-* k8s-worker-*
          User root
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null

        # Static Host Definitions (Generated from SSOT)
    ${mkVmHostConfigs}
  '';
}
