# MicroVM storage directory management
# Automatically creates required storage directories for all VMs
{
  lib,
  pkgs,
  data,
  ...
}: let
  vmNames = builtins.attrNames data.vms.definitions;

  # K8s 노드 이름 필터링
  k8sNodeNames = lib.filter (name: lib.hasPrefix "k8s-" name) vmNames;

  # Extract all VM storage paths from constants
  vmStoragePaths =
    lib.mapAttrsToList (
      _: vm:
        if vm ? storage && vm.storage ? source
        then vm.storage.source
        else null
    )
    data.vms.definitions;

  # Filter out nulls and get unique paths
  storageDirs = lib.filter (path: path != null) vmStoragePaths;

  # SSH host key directories for each VM
  sshHostKeyDirs = map (name: "/var/lib/microvms/${name}/ssh") vmNames;

  # 홈 디렉토리 - .p10k.zsh, .zsh_history 등 영속화
  # microvm 소유로 생성 (부모 디렉토리와 동일한 소유자여야 tmpfiles 보안 검사 통과)
  homeParentDirs = map (name: "/var/lib/microvms/${name}/home") vmNames;
  homeRootDirs = map (name: "/var/lib/microvms/${name}/home/root") vmNames;

  # K8s 노드 영구 저장 디렉토리 (kubeadm 기반)
  k8sConfigDirs = map (name: "/var/lib/microvms/${name}/kubernetes") k8sNodeNames;
  k8sEtcdDirs = map (name: "/var/lib/microvms/${name}/etcd") data.vms.k8s.masters;
in {
  # Create storage directories using systemd-tmpfiles
  systemd.tmpfiles.rules =
    map (path: "d ${path} 0755 microvm kvm - -") storageDirs
    # SSH host key directories (persistent across VM restarts)
    ++ map (path: "d ${path} 0700 microvm kvm - -") sshHostKeyDirs
    # 홈 디렉토리 (microvm 소유로 생성하여 tmpfiles 보안 검사 통과)
    ++ map (path: "d ${path} 0755 microvm kvm - -") homeParentDirs
    ++ map (path: "d ${path} 0700 microvm kvm - -") homeRootDirs
    # K8s 노드 영구 저장 디렉토리 (kubeadm)
    ++ map (path: "d ${path} 0755 microvm kvm - -") k8sConfigDirs
    ++ [
      # Ensure base directories exist
      "d /var/lib/microvms 0755 microvm kvm - -"
      "d /var/lib/microvms/iso 0755 microvm kvm - -"
    ]
    # etcd storage for all control-plane nodes (must be 0700 for security)
    ++ map (path: "d ${path} 0700 microvm kvm - -") k8sEtcdDirs;

  # Ensure new tmpfiles rules are applied immediately on nixos-rebuild switch
  # so microvm units can start without requiring a reboot/manual tmpfiles run.
  system.activationScripts.microvmStorageDirs.text = ''
    ${pkgs.systemd}/bin/systemd-tmpfiles --create /etc/tmpfiles.d/00-nixos.conf
  '';
}
