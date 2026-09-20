# Disko configuration for homelab-2 bare-metal Kubernetes worker.
# WARNING: This will ERASE ALL DATA on /dev/nvme0n1.
_: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["defaults" "umask=0077"];
            };
          };

          swap = {
            size = "16G";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };

          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "noatime"
                "errors=remount-ro"
              ];
            };
          };
        };
      };
    };
  };

  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "30%";
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
}
