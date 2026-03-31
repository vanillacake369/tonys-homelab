# VM Persistence & Secrets Profile
# Handles storage mounts, SSH host keys, and shared secrets
{
  config,
  lib,
  pkgs,
  data,
  microvmTarget,
  specialArgs,
  ...
}: let
  vmName = microvmTarget;
  vmInfo = data.vms.definitions.${vmName};
  vmSecretsPath = specialArgs.vmSecretsPath or "/run/host-secrets";

  # Helper to create virtiofs share
  mkShare = source: mountPoint: tag: {
    inherit source mountPoint tag;
    proto = "virtiofs";
  };

  # Helper to create virtiofs mount
  mkMount = tag: {
    device = tag;
    fsType = "virtiofs";
    neededForBoot = true;
  };
in {
  # ------------------------------------------------------------
  # MicroVM Shares (virtiofs)
  # ------------------------------------------------------------
  microvm.shares =
    [
      # 1. SSH Host Key Persistence
      (mkShare "/var/lib/microvms/${vmName}/ssh" "/persistent/ssh" "ssh-host-keys")
      # 2. Shared Secrets
      (mkShare "/run/secrets-for-users" "${vmSecretsPath}/users" "secrets-users")
      # 5. Home Directory Persistence
      (mkShare "/var/lib/microvms/${vmName}/home/root" "/root" "home-root")
    ]
    # 3. Generic Storage Mount
    ++ lib.optionals (vmInfo ? storage) [
      (mkShare vmInfo.storage.source vmInfo.storage.mountPoint vmInfo.storage.tag)
    ]
    # 4. Kubernetes Specific Persistence
    ++ lib.optionals (lib.hasPrefix "k8s-" vmName) [
      (mkShare "/var/lib/microvms/${vmName}/kubernetes" "/etc/kubernetes" "k8s-config")
    ]
    # K8s Master etcd
    ++ lib.optionals (vmName == "k8s-master") [
      (mkShare "/var/lib/microvms/${vmName}/etcd" "/var/lib/etcd" "k8s-etcd")
    ];

  # ------------------------------------------------------------
  # File Systems (Mounts)
  # ------------------------------------------------------------
  fileSystems =
    {
      "/persistent/ssh" = mkMount "ssh-host-keys";
      "${vmSecretsPath}/users" = (mkMount "secrets-users") // {options = ["ro"];};
      "/root" = mkMount "home-root";
    }
    // lib.optionalAttrs (vmInfo ? storage) {
      ${vmInfo.storage.mountPoint} = mkMount vmInfo.storage.tag;
    }
    // lib.optionalAttrs (lib.hasPrefix "k8s-" vmName) {
      "/etc/kubernetes" = mkMount "k8s-config";
    }
    // lib.optionalAttrs (vmName == "k8s-master") {
      "/var/lib/etcd" = mkMount "k8s-etcd";
    };

  # ------------------------------------------------------------
  # Additional Persistence Settings
  # ------------------------------------------------------------
  services.openssh.hostKeys = lib.mkForce [
    {
      path = "/persistent/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
    {
      path = "/persistent/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
  ];

  # Kubelet Disk Image (Volume)
  microvm.volumes = lib.optionals (vmInfo ? kubeletVolume) [
    {
      image = "/var/lib/microvms/${vmName}/kubelet.img";
      mountPoint = "/var/lib/kubelet";
      size = vmInfo.kubeletVolume.size or 2048;
      fsType = "ext4";
      autoCreate = true;
    }
  ];
}
