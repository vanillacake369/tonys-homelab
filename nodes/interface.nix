# IaC Contract
# - ip
# - role
# - mac
# - user
# - custom 설정
# NOTE : https://sraka.xyz/posts/contracts.html 참고
{
  lib,
  config,
  ...
}: {
  options.node = {
    ip = lib.mkOption {
      type = lib.types.str;
      description = "노드 외부/내부 IP";
    };
    hostType = lib.mkOption {
      type = lib.types.enum ["physical" "vm"];
      description = "Host Type";
    };
    role = lib.mkOption {
      type = lib.types.enum ["k8s-master" "k8s-worker" "host"];
      description = "Node Role";
    };
    mac = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "MAC 주소";
      default = null;
    };
    parentHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "이 노드가 위치한 물리 호스트의 이름";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "SSH 배포 사용자 (deployment.targetUser)";
    };
  };
  config.assertions = [
    {
      assertion = config.node.ip != "";
      message = "IaC Contract: 각 노드는 IP 선언이 필요합니다.";
    }
    {
      assertion = config.node.hostType == "vm" -> config.node.parentHost != null;
      message = "IaC Contract: VM 노드(${config.networking.hostName})는 반드시 parentHost 선언이 필요합니다.";
    }
    {
      assertion = config.node.role != null;
      message = "IaC Contract: 각 노드는 Role 선언이 필요합니다.";
    }
    {
      # VM 노드만 TAP 인터페이스용 MAC 주소 필요 (물리 호스트는 불필요)
      assertion = config.node.hostType == "vm" -> config.node.mac != null;
      message = "IaC Contract: VM 노드(${config.networking.hostName})는 MAC 주소 선언이 필요합니다.";
    }
  ];
}
