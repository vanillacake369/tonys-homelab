set -l just_user_completions "$HOME/.config/fish/completions"
if not contains -- "$just_user_completions" $fish_complete_path
    set -p fish_complete_path "$just_user_completions"
else if test "$fish_complete_path[1]" != "$just_user_completions"
    set -e fish_complete_path[(contains -i -- "$just_user_completions" $fish_complete_path)]
    set -p fish_complete_path "$just_user_completions"
end
