> [!NOTE]
>
> IDEAOLOY :
> Aspect sliced action based commands

> [!TIP]
>
> REQUIREMENTS :
>
> - auto-detect the enviroment changes
>   e.g. future host scaffold detects node enviroment,
>   make new file of node name by given args
>   in ./nodes/physical/
> - reconcile
> - guardrail -> proccess -> verification

> [!IMPORTANT]
>
> ROADMAP:
>
> - [ ] make physical hosts multi-node ready
>     - [ ] remove singleton `network.wan.host`
>     - [ ] use `network.hosts.<hostname>.uplink.*`
>     - [ ] move host-specific NIC name into topology / node config
>     - [ ] decide VLAN gateway/address strategy for multiple physical hosts
>     - [ ] extract reusable physical-hypervisor config from `homelab-1.nix`
> - [ ] declare `homelab-2`
>     - [ ] add `network.topology.hosts.homelab-2`
>     - [ ] add `nodes/physical/homelab-2.nix`
>     - [ ] add `nodes/physical/disko-config-homelab-2.nix`
>     - [ ] configure hardware-specific options
>     - [ ] configure NIC / bridge
> - [ ] bootstrap physical node
>     - [ ] BIOS / UEFI -> plain NixOS installer
>     - [ ] setup temporary network
>         - [ ] ethernet preferred
>         - [ ] wifi only as manual fallback
>     - [ ] enable SSH + authorized key
>     - [ ] probe hardware
>         - [ ] disk
>         - [ ] NIC
>         - [ ] CPU / GPU
>         - [ ] firmware / boot mode
>     - [ ] generate/preserve SSH host key
>     - [ ] add homelab-2 age recipient to `.sops.yaml`
>     - [ ] `sops updatekeys secrets/secrets.yaml`
>     - [ ] install via disko + nixos-anywhere
>     - [ ] reboot
> - [ ] reconcile installed node
>     - [ ] `just host ssh homelab-2`
>     - [ ] `just host plan homelab-2`
>     - [ ] `CONFIRM_DEPLOY=homelab just host apply homelab-2`
>     - [ ] `just host verify homelab-2`
>     - [ ] verify network / libvirt / tailscale / sops
> - [ ] automate bootstrap
>     - [ ] hardware / disk / NIC probe
>     - [ ] render or validate node config
>     - [ ] sops recipient validation
>     - [ ] destructive install confirmation
>     - [ ] nixos-anywhere execution
>     - [ ] post-install health checks

## Current strangler surface

현재 단계에서는 새 domain namespace를 늘리지 않고, 이미 공개된 운영 API를 먼저 완성한다.

- just host
    - list
    - add: declared host onboarding preflight / SOPS recipient validation
    - install: guarded nixos-anywhere install
    - ssh
    - plan
    - apply
    - verify
    - gc

- just vm
    - list
    - build
    - provision
    - ssh
    - start/stop/restart
    - plan
    - apply
    - destroy
    - check
    - verify
    - gc

- just k8s
    - ssh
    - bootstrap
    - verify
    - check
    - deploy
    - clean
    - reset
    - reset-deploy
    - join: kubeadm bootstrap/join
    - reconcile: manifest check -> join -> verify

현재 public surface는 resource namespace 중심으로 유지한다.

- just check
- just host
- just vm
- just k8s
- just gitops
- just manifest
- just nix
- just setup

## First namespace strangler

- just nix
    - check -> just check nix
    - update -> flake input update
    - gc -> topology scoped garbage collection

- just setup
    - completions -> repository completion install
    - hooks -> repository git hook install

`gitops`와 `manifest` namespace는 지금 추가하지 않는다. 현재 목표는 CLI surface completion이지 새 domain 확장이 아니다.

> [!NOTE]
>
> 실제 노드 추가 처리 과정
>
> ```bash
> # 이더넷 / Wi-Fi 연결 확인
> ip link
>
> # 1) rfkill 블로킹 여부 확인
> rfkill
>
> # 2) 이더넷을 꼽던지 nmcli 를 통해 연결
> nmcli device status
> nmcli radio wifi on
> sudo nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
>
> # 3) 연결 정상 여부 확인
> ip addr show ${net_card}
> ping -c 3 8.8.8.8
> ```
>
> ```bash
> # SSH 연결
> # 1) root password 설정
> sudo passwd root
>
> # 2) SSH daemon 시작
> sudo systemctl start sshd
>
> # 3) 확인
> systemctl status sshd
> ss -lntp | grep :22
>
> # 4) IP 확인
> ip -br addr
> ```
>
> ```
> # nix 파일 추가
> # just 명령어로 자동화 가능!!
> tonys-homelab/nodes/physical/homelab-*.nix
> tonys-homelab/nodes/physical/disko-config-homelab-2.nix
> ```
>
> ```
> # login pub key 등록
>
> # host가 소유한 SSH login public key
> sshpass -p "your_actual_password” ssh username@192.168.1.50 'cat ~/.ssh/id_ed25519.pub’ > secrets/hosts/host-homelab-2-ed25519.pub
>
> # sops-nix recipient는 별도 SSH daemon host identity에서 산출한다.
> # 이미 .sops.yaml에 등록되어 있으면 다시 처리하지 않는다.
> sshpass -p "your_actual_password” ssh root@192.168.1.50 'cat /etc/ssh/ssh_host_ed25519_key.pub’ > /tmp/homelab-2-ssh_host-ed25519.pub
>
> # 2) ssh-to-age 를 통해 ssh pub key 를 age recipient 변환
> ssh-to-age < /tmp/homelab-2-ssh_host-ed25519.pub
>
> # 3) 출력된 age1... recipient를 .sops.yaml에 추가
> vim .sops.yaml
>
> # 4) 기존 secrets의 recipient 갱신
> sops updatekeys secrets/secrets.yaml
> ```
>
> ```
> # Apply 처리
> env SSHPASS=’${pw}’ nix run github:nix-community/nixos-anywhere --
> --print-build-logs
> --debug
> --env-password
> --copy-host-keys
> --build-on-remote
> --flake .#homelab-2
> --target-host root@192.168.45.29
> --ssh-option StrictHostKeyChecking=no
> ```
