# lib/mk-libvirt.nix
# libvirt VM 인프라 생성 pure function
# 모든 값은 외부에서 주입 — topology 직접 import 없음
{
  lib,
  pkgs,
  vms,
  bridge,
  vlanId,
}: let
  vmList = lib.attrsToList vms;

  mkDomainXml = name: vm: ''
    <domain type='kvm'>
      <name>${name}</name>
      <memory unit='MiB'>${toString vm.mem}</memory>
      <vcpu>${toString vm.vcpu}</vcpu>
      <os>
        <type arch='x86_64'>hvm</type>
        <boot dev='hd'/>
      </os>
      <features><acpi/><apic/></features>
      <cpu mode='host-passthrough'/>
      <devices>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2' discard='unmap'/>
          <source file='/var/lib/libvirt/images/${name}.qcow2'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <interface type='bridge'>
          <source bridge='${bridge}'/>
          <mac address='${vm.mac}'/>
          <target dev='${vm.tapId}'/>
          <model type='virtio'/>
        </interface>
        <serial type='pty'><target port='0'/></serial>
        <console type='pty'><target type='serial' port='0'/></console>
        <rng model='virtio'>
          <backend model='random'>/dev/urandom</backend>
        </rng>
      </devices>
    </domain>
  '';

  mkDomainServices = builtins.listToAttrs (map (entry: let
      name = entry.name;
      vm = entry.value;
      xmlFile = pkgs.writeText "vm-${name}.xml" (mkDomainXml name vm);
    in {
      name = "vm-${name}";
      value = {
        description = "Libvirt domain: ${name}";
        after = ["libvirtd.service"];
        requires = ["libvirtd.service"];
        wantedBy = ["multi-user.target"];
        path = [pkgs.libvirt pkgs.qemu_kvm pkgs.coreutils pkgs.iproute2 pkgs.bridge-utils pkgs.gawk pkgs.gnugrep pkgs.grub2 pkgs.util-linux];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop = "${pkgs.libvirt}/bin/virsh destroy ${name}";
        };
        script = ''
          mkdir -p /var/lib/libvirt/images

          # 디스크 이미지가 없으면: base 이미지 복사 또는 빈 디스크 생성
          if [ ! -f "/var/lib/libvirt/images/${name}.qcow2" ]; then
            if [ -f "/var/lib/libvirt/images/base/${name}.qcow2" ]; then
              echo "Provisioning ${name} from base image..."
              cp "/var/lib/libvirt/images/base/${name}.qcow2" "/var/lib/libvirt/images/${name}.qcow2"
              chmod 644 "/var/lib/libvirt/images/${name}.qcow2"
              qemu-img resize "/var/lib/libvirt/images/${name}.qcow2" "${toString vm.diskSize}G"
            else
              echo "WARNING: No base image for ${name}, creating empty disk (${toString vm.diskSize}G)"
              qemu-img create -f qcow2 "/var/lib/libvirt/images/${name}.qcow2" "${toString vm.diskSize}G"
            fi
          fi

          # 도메인 정의/갱신 (idempotent)
          if virsh dominfo "${name}" &>/dev/null; then
            if virsh list --name | grep -q "^${name}$"; then
              echo "Domain ${name} is running, skipping redefine."
            else
              virsh undefine "${name}" 2>/dev/null || true
              virsh define "${xmlFile}"
            fi
          else
            virsh define "${xmlFile}"
          fi
          virsh autostart ${name} 2>/dev/null || true

          # VM 시작 (이미 실행 중이면 무시)
          if ! virsh list --name | grep -q "^${name}$"; then
            echo "Starting VM ${name}..."
            virsh start ${name} || true
          fi

          # VLAN 할당 (hook fallback — TAP 생성 대기 후 적용)
          for i in $(seq 1 10); do
            TAP=$(virsh domiflist "${name}" 2>/dev/null | awk 'NR>2 && $1!="" {print $1; exit}')
            if [ -n "$TAP" ]; then
              bridge vlan add dev "$TAP" vid ${toString vlanId} pvid untagged 2>/dev/null || true
              bridge vlan del dev "$TAP" vid 1 2>/dev/null || true
              echo "VLAN ${toString vlanId} applied to $TAP"
              break
            fi
            sleep 1
          done
        '';
      };
    })
    vmList);

  vlanHookScript = pkgs.writeScript "qemu-hook" ''
    #!/bin/sh
    GUEST_NAME="$1"
    ACTION="$2"
    if [ "$ACTION" = "started" ] || [ "$ACTION" = "reconnect" ]; then
      for i in $(seq 1 10); do
        TAP=$(${pkgs.libvirt}/bin/virsh domiflist "$GUEST_NAME" 2>/dev/null | awk 'NR>2 && $1!="" {print $1; exit}')
        if [ -n "$TAP" ]; then
          ${pkgs.iproute2}/sbin/bridge vlan add dev "$TAP" vid ${toString vlanId} pvid untagged 2>/dev/null || true
          ${pkgs.iproute2}/sbin/bridge vlan del dev "$TAP" vid 1 2>/dev/null || true
          break
        fi
        sleep 1
      done
    fi
  '';
in {
  domainServices = mkDomainServices;
  hookRules = [
    "d /etc/libvirt/hooks 0755 root root -"
    "L+ /etc/libvirt/hooks/qemu - - - - ${vlanHookScript}"
  ];
}
