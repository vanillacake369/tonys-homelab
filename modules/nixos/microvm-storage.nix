# MicroVM storage directory management
# Automatically creates required storage directories for all VMs
{
  lib,
  homelabConstants,
  ...
}: let
  vmNames = builtins.attrNames homelabConstants.vms;

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
    homelabConstants.vms;

  # Filter out nulls and get unique paths
  storageDirs = lib.filter (path: path != null) vmStoragePaths;

  # SSH host key directories for each VM
  sshHostKeyDirs = map (name: "/var/lib/microvms/${name}/ssh") vmNames;

  # K8s 노드 영구 저장 디렉토리 (kubeadm 기반)
  # /etc/kubernetes 모든 K8s 노드에 필요 (인증서, manifests, kubeconfig)
  # /var/lib/etcd는 k8s-master만 필요
  # 주의: /var/lib/kubelet은 virtiofs로 마운트하면 안 됨 (cAdvisor 호환성 문제)
  k8sConfigDirs = map (name: "/var/lib/microvms/${name}/kubernetes") k8sNodeNames;
  k8sEtcdDir = "/var/lib/microvms/k8s-master/etcd";
in {
  # Create storage directories using systemd-tmpfiles
  systemd.tmpfiles.rules =
    map (path: "d ${path} 0755 microvm kvm - -") storageDirs
    # SSH host key directories (persistent across VM restarts)
    ++ map (path: "d ${path} 0700 microvm kvm - -") sshHostKeyDirs
    # K8s 노드 영구 저장 디렉토리 (kubeadm)
    ++ map (path: "d ${path} 0755 microvm kvm - -") k8sConfigDirs
    ++ [
      # Ensure base directories exist
      "d /var/lib/microvms 0755 microvm kvm - -"
      "d /var/lib/microvms/iso 0755 microvm kvm - -"
      # etcd storage for k8s-master (must be 0700 for security)
      "d ${k8sEtcdDir} 0700 microvm kvm - -"
    ];
}
