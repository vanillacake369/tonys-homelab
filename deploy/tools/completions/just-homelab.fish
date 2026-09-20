function __just_homelab_root
    command git rev-parse --show-toplevel 2>/dev/null
    or pwd
end

function __just_homelab_is_repo
    set -l root (__just_homelab_root)
    test -f "$root/network/topology.nix"
    and test -d "$root/deploy/platform/apps"
    and test -f "$root/justfile"
end

function __just_homelab_topology_names --argument-names kind
    set -l root (__just_homelab_root)
    command nix eval --impure --json --expr "builtins.attrNames (import $root/network/topology.nix).$kind" 2>/dev/null | jq -r '.[]' 2>/dev/null
end

function __just_homelab_topology_all_names
    __just_homelab_topology_names hosts
    __just_homelab_topology_names vms
end

function __just_homelab_k8s_names
    set -l root (__just_homelab_root)
    command nix eval --impure --json --expr "let inv = import $root/ansible/inventory.nix {}; in inv.k8s_masters.hosts ++ inv.k8s_workers.hosts" 2>/dev/null | jq -r '.[]' 2>/dev/null
end

function __just_homelab_recipes
    printf '%s\t%s\n' check 'run local guard checks'
    printf '%s\t%s\n' gitops 'manage Flux GitOps reconciliation'
    printf '%s\t%s\n' host 'manage physical hosts'
    printf '%s\t%s\n' k8s 'manage Kubernetes cluster lifecycle'
    printf '%s\t%s\n' manifest 'manage rendered manifests'
    printf '%s\t%s\n' nix 'manage Nix checks, updates, and GC'
    printf '%s\t%s\n' setup 'install local developer integrations'
    printf '%s\t%s\n' vm 'manage libvirt VMs'
end

function __just_homelab_check_targets
    printf '%s\t%s\n' all 'run every local guardrail'
    printf '%s\t%s\n' generated 'check CUE generated manifests are current'
    printf '%s\t%s\n' nix 'run Nix formatting, lint, and flake checks'
    printf '%s\t%s\n' k8s 'validate Kubernetes manifests'
    printf '%s\t%s\n' yaml 'lint YAML files'
    printf '%s\t%s\n' shell 'lint shell scripts'
    printf '%s\t%s\n' actions 'lint GitHub Actions workflows'
    printf '%s\t%s\n' secrets 'scan worktree for leaked secrets'
    printf '%s\t%s\n' docs 'check documentation command references'
    printf '%s\t%s\n' hooks 'check repository git hooks'
    printf '%s\t%s\n' recipes 'check just command contracts'
end

function __just_homelab_host_actions
    printf '%s\t%s\n' list 'list declared physical hosts'
    printf '%s\t%s\n' add 'validate onboarding state for a host'
    printf '%s\t%s\n' install 'bootstrap a declared host with nixos-anywhere'
    printf '%s\t%s\n' ssh 'connect to a physical host'
    printf '%s\t%s\n' plan 'dry-activate a physical host'
    printf '%s\t%s\n' apply 'apply desired state to a physical host'
    printf '%s\t%s\n' verify 'verify runtime host health'
    printf '%s\t%s\n' gc 'run garbage collection on a physical host'
end

function __just_homelab_vm_actions
    printf '%s\t%s\n' list 'list declared VMs and reachability'
    printf '%s\t%s\n' status 'show VM reachability'
    printf '%s\t%s\n' build 'build VM base images on parent hosts'
    printf '%s\t%s\n' provision 'create or refresh VM runtime state'
    printf '%s\t%s\n' ssh 'connect to a VM through its parent host'
    printf '%s\t%s\n' start 'start VM systemd units'
    printf '%s\t%s\n' stop 'stop VM systemd units'
    printf '%s\t%s\n' restart 'restart VM systemd units'
    printf '%s\t%s\n' plan 'dry-activate a VM'
    printf '%s\t%s\n' apply 'apply desired state to a VM'
    printf '%s\t%s\n' destroy 'destroy VM runtime state'
    printf '%s\t%s\n' check 'check VM reachability'
    printf '%s\t%s\n' verify 'verify VM reachability'
    printf '%s\t%s\n' gc 'run garbage collection on a VM'
    printf '%s\t%s\n' cleanup 'remove stale libvirt domains'
    printf '%s\t%s\n' sync 'cleanup, build, then provision VMs'
end

function __just_homelab_k8s_actions
    printf '%s\t%s\n' ssh 'connect to the Kubernetes master'
    printf '%s\t%s\n' bootstrap 'run kubeadm bootstrap tasks'
    printf '%s\t%s\n' verify 'check cluster runtime health'
    printf '%s\t%s\n' check 'validate Kubernetes manifests locally'
    printf '%s\t%s\n' deploy 'bootstrap then verify the cluster'
    printf '%s\t%s\n' clean 'reset cluster state with confirmation'
    printf '%s\t%s\n' reset 'alias for clean'
    printf '%s\t%s\n' reset-deploy 'reset, bootstrap, then verify'
    printf '%s\t%s\n' bootstrap-sops-age 'install Flux SOPS age secret'
    printf '%s\t%s\n' verify-sops-age 'verify Flux SOPS age secret'
    printf '%s\t%s\n' join 'join one or all k8s nodes'
    printf '%s\t%s\n' reconcile 'check manifests, join, then verify'
end

function __just_homelab_gitops_actions
    printf '%s\t%s\n' status 'show Flux resource status'
    printf '%s\t%s\n' plan 'render generated manifests and run checks'
    printf '%s\t%s\n' reconcile 'force Flux source and kustomization reconcile'
    printf '%s\t%s\n' bootstrap 'bootstrap Flux against GitHub'
end

function __just_homelab_manifest_actions
    printf '%s\t%s\n' render 'render one generated app'
    printf '%s\t%s\n' render-all 'render all generated apps'
    printf '%s\t%s\n' check 'check one generated app'
    printf '%s\t%s\n' check-all 'check all generated apps'
    printf '%s\t%s\n' check-generated 'verify generated output is current'
    printf '%s\t%s\n' diff 'show generated manifest diff'
    printf '%s\t%s\n' clean 'remove generated manifests'
end

function __just_homelab_nix_actions
    printf '%s\t%s\n' check 'run Nix checks'
    printf '%s\t%s\n' update 'update flake inputs'
    printf '%s\t%s\n' gc 'run topology-scoped garbage collection'
end

function __just_homelab_setup_actions
    printf '%s\t%s\n' completions 'install fish and zsh completions'
    printf '%s\t%s\n' hooks 'install repository git hooks'
end

function __just_homelab_topology_names_position --argument-names kind
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and begin
        test "$tokens[2]" = nix
        and test "$tokens[3]" = gc
        and test (count $tokens) -ge 4
        and test "$tokens[4]" = "$kind"
    end
end

function __just_homelab_check_target_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = check
    and test (count $tokens) -eq 2
end

function __just_homelab_host_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = host
    and test (count $tokens) -eq 2
end

function __just_homelab_host_name_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and test "$tokens[2]" = host
    and contains -- "$tokens[3]" add install ssh plan apply verify gc
end

function __just_homelab_vm_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = vm
    and test (count $tokens) -eq 2
end

function __just_homelab_vm_name_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and test "$tokens[2]" = vm
    and contains -- "$tokens[3]" list status build provision ssh start stop restart plan apply destroy check verify gc sync
end

function __just_homelab_k8s_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = k8s
    and test (count $tokens) -eq 2
end

function __just_homelab_k8s_target_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and test "$tokens[2]" = k8s
    and contains -- "$tokens[3]" join reconcile
    and test (count $tokens) -eq 3
end

function __just_homelab_gitops_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = gitops
    and test (count $tokens) -eq 2
end

function __just_homelab_manifest_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = manifest
    and test (count $tokens) -eq 2
end

function __just_homelab_manifest_app_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and test "$tokens[2]" = manifest
    and contains -- "$tokens[3]" render check
    and test (count $tokens) -eq 3
end

function __just_homelab_nix_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = nix
    and test (count $tokens) -eq 2
end

function __just_homelab_nix_gc_target_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and test "$tokens[2]" = nix
    and test "$tokens[3]" = gc
    and test (count $tokens) -eq 3
end

function __just_homelab_setup_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = setup
    and test (count $tokens) -eq 2
end

complete -c just -e
complete -c just -f -n '__just_homelab_is_repo; and test (count (commandline -opc)) -eq 1' -a '(__just_homelab_recipes)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_topology_names_position host' -a '(__just_homelab_topology_names hosts)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_topology_names_position vm' -a '(__just_homelab_topology_names vms)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_check_target_position' -a '(__just_homelab_check_targets)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_host_action_position' -a '(__just_homelab_host_actions)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_host_name_position' -a '(__just_homelab_topology_names hosts)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_vm_action_position' -a '(__just_homelab_vm_actions)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_vm_name_position' -a '(__just_homelab_topology_names vms)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_k8s_action_position' -a '(__just_homelab_k8s_actions)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_k8s_target_position' -a 'all (__just_homelab_k8s_names)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_gitops_action_position' -a '(__just_homelab_gitops_actions)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_manifest_action_position' -a '(__just_homelab_manifest_actions)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_manifest_app_position' -a '(__just_homelab_platform_apps)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_nix_action_position' -a '(__just_homelab_nix_actions)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_nix_gc_target_position' -a 'all host-all vm-all host vm'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_setup_action_position' -a '(__just_homelab_setup_actions)'
