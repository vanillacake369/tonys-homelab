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

  # 하나의 VM 정의(name, vm.mem, vm.vcpu, vm.mac, vm.tapId 등)를 받아
  # Libvirt용 도메인 XML(<domain> ... </domain>)을 문자열로 생성
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
      </devices>
    </domain>
  '';

  # vmList 의 각 VM 에 대해
  # - XML 파일 생성
  # - 해당 XML 파일을 사용하여 virsh define + virsh autostart를 실행하는 oneshot systemd 서비스를 정의
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
        path = [pkgs.libvirt pkgs.qemu_kvm pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # 이미지 디렉토리 확인
          mkdir -p /var/lib/libvirt/images

          # 디스크 이미지가 없으면 생성
          if [ ! -f "/var/lib/libvirt/images/${name}.qcow2" ]; then
            echo "Creating disk image for ${name} (${toString vm.diskSize}G)..."
            qemu-img create -f qcow2 "/var/lib/libvirt/images/${name}.qcow2" "${toString vm.diskSize}G"
          fi

          # 도메인 정의 (이미 존재하면 UUID 충돌 방지를 위해 undefine 후 다시 정의)
          if virsh list --all --name | grep -q "^${name}$"; then
            echo "Domain ${name} already exists, re-defining..."
            virsh undefine "${name}"
          fi
          virsh define ${xmlFile}
          virsh autostart ${name}

          # VM 시작 (이미 실행 중이면 무시)
          if ! virsh list --name | grep -q "^${name}$"; then
            echo "Starting VM ${name}..."
            virsh start ${name}
          fi
        '';
      };
    })
    vmList);

  # libvirt qemu hook script 생성
  # libvirt 에서 qemu vm 시작될 때마다
  #   - virsh domiflist 를 통해 해당 VM 의 TAP 조회
  #   - TAP 에 bridge vlan 추가하여 VLAN 설정
  vlanHookScript = pkgs.writeScript "qemu-hook" ''
    #!/bin/sh
    GUEST_NAME="$1"
    ACTION="$2"
    if [ "$ACTION" = "started" ]; then
      TAP=$(virsh domiflist "$GUEST_NAME" 2>/dev/null | awk 'NR>2 && $1!="" {print $1; exit}')
      if [ -n "$TAP" ]; then
        bridge vlan add dev "$TAP" vid ${toString vlanId} pvid untagged 2>/dev/null || true
      fi
    fi
  '';
in {
  domainServices = mkDomainServices;

  # /etc/libvirt/hooks/qemu에 vlanHookScript를 심볼릭 링크로 연결
  # 이를 통해 Libvirt가 QEMU 이벤트마다 -- VM 시작/종료
  # 위 qemu-hook 스크립트를 호출
  hookRules = [
    "d /etc/libvirt/hooks 0755 root root -"
    "L+ /etc/libvirt/hooks/qemu - - - - ${vlanHookScript}"
  ];
}
