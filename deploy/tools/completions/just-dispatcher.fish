set -g __just_dispatch_completion_dir (path dirname (status --current-filename))

function __just_dispatch_root
    command git rev-parse --show-toplevel 2>/dev/null
    or pwd
end

function __just_dispatch_source_helpers
    if test -r "$__just_dispatch_completion_dir/just-tonys-homelab.fish"
        source "$__just_dispatch_completion_dir/just-tonys-homelab.fish"
    else if test -r "$__just_dispatch_completion_dir/just-homelab.fish"
        source "$__just_dispatch_completion_dir/just-homelab.fish"
    end
    test -r "$__just_dispatch_completion_dir/just-tonys-interview.fish"; and source "$__just_dispatch_completion_dir/just-tonys-interview.fish"
end

function __just_dispatch_known_repo
    functions -q __just_homelab_is_repo
    and __just_homelab_is_repo
    and return 0

    functions -q __just_tonys_interview_is_repo
    and __just_tonys_interview_is_repo
    and return 0

    return 1
end

function __just_dispatch_generic_recipes
    command just --summary --list-submodules 2>/dev/null \
        | string split ' ' \
        | awk -F'::' 'NF == 1 { print $1 } NF > 1 { print $1 }' \
        | awk 'NF && !seen[$0]++'
end

function __just_dispatch_generic_subcommands --argument-names module
    command just --summary --list-submodules 2>/dev/null \
        | string split ' ' \
        | awk -F'::' -v module="$module" 'NF > 1 && $1 == module { print $2 }'
end

function __just_dispatch_generic_recipe_position
    not __just_dispatch_known_repo
    and test (count (commandline -opc)) -eq 1
end

function __just_dispatch_generic_subcommand_position
    set -l tokens (commandline -opc)
    not __just_dispatch_known_repo
    and test (count $tokens) -eq 2
end

complete -c just -e
__just_dispatch_source_helpers
complete -c just -f -n '__just_dispatch_generic_recipe_position' -a '(__just_dispatch_generic_recipes)'
complete -c just -f -n '__just_dispatch_generic_subcommand_position' -a '(__just_dispatch_generic_subcommands (commandline -opc)[2])'
