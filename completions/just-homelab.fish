JUST_COMPLETE=fish just | source

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

function __just_homelab_platform_apps
    set -l root (__just_homelab_root)
    command find "$root/deploy/platform/apps" -maxdepth 1 -type f -name '*.cue' 2>/dev/null | sed 's#^.*/##; s#\.cue$##'
end

function __just_homelab_topology_subcommand_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = gc
    and test (count $tokens) -eq 2
end

function __just_homelab_plan_apply_domain_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and contains -- "$tokens[2]" apply plan
    and test (count $tokens) -eq 2
end

function __just_homelab_infra_target_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and contains -- "$tokens[2]" apply plan
    and test "$tokens[3]" = infra
    and test (count $tokens) -eq 3
end

function __just_homelab_topology_names_position --argument-names kind
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and begin
        test "$tokens[2]" = gc
        and test "$tokens[3]" = "$kind"
        or contains -- "$tokens[2]" apply plan
        and test "$tokens[3]" = infra
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

function __just_homelab_manifest_app_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and begin
        test "$tokens[2]" = manifest
        and contains -- "$tokens[3]" render check
    end
end

function __just_homelab_manifest_action_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = manifest
    and test (count $tokens) -eq 2
end

function __just_homelab_single_target_position --argument-names recipe target
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2
    and test "$tokens[2]" = "$recipe"
    and test (count $tokens) -eq 2
end

function __just_homelab_bootstrap_provider_position
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3
    and test "$tokens[2]" = bootstrap
    and test "$tokens[3]" = gitops
    and test (count $tokens) -eq 3
end

complete -c just -f -n '__just_homelab_is_repo; and test (count (commandline -opc)) -eq 1' -a '(just --summary)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_topology_subcommand_position' -a 'all host-all vm-all host vm'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_plan_apply_domain_position' -a 'gitops infra'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_infra_target_position' -a 'all host-all vm-all host vm'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_topology_names_position host' -a '(__just_homelab_topology_names hosts)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_topology_names_position vm' -a '(__just_homelab_topology_names vms)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_check_target_position' -a 'all nix k8s yaml shell actions secrets docs hooks recipes'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_manifest_action_position' -a 'render render-all check check-all check-generated diff clean'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_manifest_app_position' -a '(__just_homelab_platform_apps)'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_single_target_position bootstrap gitops' -a 'gitops'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_bootstrap_provider_position' -a 'flux'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_single_target_position status gitops' -a 'gitops'
complete -c just -f -n '__just_homelab_is_repo; and __just_homelab_single_target_position reconcile gitops' -a 'gitops'
