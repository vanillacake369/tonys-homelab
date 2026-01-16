# Network configuration for homelab server
# TODO : 예시코드. 실제 구성도에 맞춰 수정할 것
# TODO : networking.bridges."vmbr0".interfaces = [ "eth0" ]; # WAN NIC
# TODO : networking.bridges."vmbr1".interfaces = [ "eth1" ]; # LAN NIC
_: {
  networking = {
    hostName = "homelab";

    networkmanager = {
      enable = true;
    };

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
}
