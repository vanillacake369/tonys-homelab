# Disko configuration for bare-metal server installation
# This replaces Proxmox with NixOS on the physical server
# WARNING: This will ERASE ALL DATA on the target disk
_: {
  # ==========================================
  # 1. Disko 설정 (discard 제거)
  # ==========================================
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          # ==========================================
          # 부팅 영역
          # ==========================================
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

          # ==========================================
          # 스왑
          # ==========================================
          swap = {
            size = "16G";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };

          # ==========================================
          # LVM Physical Volume
          # ==========================================
          lvm = {
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "homelab_vg";
            };
          };
        };
      };
    };

    lvm_vg.homelab_vg = {
      type = "lvm_vg";
      lvs = {
        # ==========================================
        # Tier 1: 시스템 (Thick - 절대 보호)
        # ==========================================
        root = {
          size = "200G"; # ⭐ NixOS + /nix/store 통합
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

        # ==========================================
        # Tier 2: VM Thin Pool (유연한 오버커밋)
        # ==========================================
        vm_thinpool = {
          size = "380G"; # 실제 물리 할당 (disk space optimized)
          lvm_type = "thin-pool";
          # Thin Pool 설정
          extraArgs = [
            "--chunksize"
            "64K" # SSD 최적화
            "--poolmetadatasize"
            "1G" # 메타데이터
          ];
        };

        # Thin LV: VM 통합 볼륨
        vms = {
          size = "800G"; # ⚠️ 논리적 크기 (오버커밋 2배)
          lvm_type = "thinlv";
          pool = "vm_thinpool";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/libvirt/images";
            mountOptions = [
              "noatime"
              "lazytime" # 메타데이터 쓰기 지연
            ];
          };
        };

        # ==========================================
        # Tier 3: Data Thin Pool (앱 데이터)
        # ==========================================
        data_thinpool = {
          size = "300G"; # 실제 물리 할당
          lvm_type = "thin-pool";
          extraArgs = [
            "--chunksize"
            "128K"
            "--poolmetadatasize"
            "500M"
          ];
        };

        # Thin LV: 통합 데이터 볼륨
        data = {
          size = "600G"; # 논리적 크기 (오버커밋 2배)
          lvm_type = "thinlv";
          pool = "data_thinpool";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/data";
            mountOptions = [
              "noatime"
              "lazytime"
            ];
          };
        };

        # ==========================================
        # Vault 전용 (보안 격리)
        # ==========================================
        vault = {
          size = "20G"; # Thick - 중요 데이터
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/vault";
            mountOptions = [
              "noatime"
              "data=ordered" # 무결성 우선
            ];
          };
        };
      };
    };
  };

  # ==========================================
  # 2. fstrim 자동화
  # ==========================================
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # ==========================================
  # 3. LVM 자동 확장
  # ==========================================
  environment.etc."lvm/lvm.conf".text = ''
    activation {
      thin_pool_autoextend_threshold = 80
      thin_pool_autoextend_percent = 20
    }
  '';

  systemd.services.lvm2-monitor.enable = true;

  # ==========================================
  # 4. tmpfs for /tmp
  # ==========================================
  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "30%"; # 9.6GB
  };
}
