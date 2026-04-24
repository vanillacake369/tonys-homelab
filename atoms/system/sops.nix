{
  config,
  lib,
  ...
}: {
  sops = {
    # 모든 노드(물리/VM)에서 공통으로 사용할 시크릿 파일 경로
    defaultSopsFile = ../../secrets/secrets.yaml;

    # VM인 경우 Colmena가 주입한 마스터 키를 우선 사용
    age.keyFile = lib.mkIf (config.node.hostType == "vm") "/var/lib/sops-nix/vm-master.key";

    # 물리 호스트는 기존대로 SSH 키 사용
    age.sshKeyPaths = lib.mkIf (config.node.hostType == "physical") ["/etc/ssh/ssh_host_ed25519_key"];
  };
}
