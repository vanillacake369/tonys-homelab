# VM Base Profile
# "Data to Option" Adapter
#
# 이 모듈은 data.vms.definitions에 정의된 정보를 바탕으로
# MicroVM 하드웨어(CPU, RAM, MAC)와 네트워킹(IP, Gateway)을 자동으로 설정합니다.
{
  config,
  lib,
  pkgs,
  data,
  microvmTarget,
  ...
}: let
  # microvmTarget은 mk-microvms.nix에서 specialArgs로 전달됨
  vmName = microvmTarget;
  vmInfo = data.vms.definitions.${vmName};
  vlanInfo = data.network.vlans.${vmInfo.vlan};
in {
  # ------------------------------------------------------------
  # MicroVM 하드웨어 설정 (데이터 기반 자동화)
  # ------------------------------------------------------------
  microvm = {
    vcpu = lib.mkDefault vmInfo.vcpu;
    mem = lib.mkDefault vmInfo.mem;
    vsock.cid = lib.mkDefault vmInfo.vsockCid;

    interfaces = [
      {
        type = "tap";
        id = vmInfo.tapId;
        mac = vmInfo.mac;
      }
    ];
  };

  # ------------------------------------------------------------
  # 네트워킹 설정 (systemd-networkd)
  # ------------------------------------------------------------
  networking = {
    hostName = lib.mkForce vmInfo.hostname;
    useDHCP = false;
    nameservers = data.network.dns;
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = ["${vmInfo.ip}/${toString vlanInfo.prefixLength}"];
    gateway = [vlanInfo.gateway];
    dns = data.network.dns;
    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = false;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # ------------------------------------------------------------
  # 기본 서비스 및 보안
  # ------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  networking.firewall.enable = true;
  
  # State Version (SSOT)
  system.stateVersion = data.hosts.common.stateVersion;
}
