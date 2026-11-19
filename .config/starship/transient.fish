# Transient prompt for fish: past prompts collapse to two blank lines (the
# add_newline gap, then one in place of the details bar) and the character
# module, so the prompt keeps its height.
# Source after `starship init fish | source`.
function starship_transient_prompt_func
    echo
    echo
    starship module character $argv
end
enable_transience
