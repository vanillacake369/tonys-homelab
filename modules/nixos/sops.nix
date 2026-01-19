{inputs, ...}: {
  imports = [inputs.sops-nix.nixosModules.sops];

  sops = {
    # 모든 비밀값의 기본 경로 설정
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    # 복호화를 위한 호스트 키 경로
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  };
}
