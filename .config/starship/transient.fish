# Transient prompt for fish: past prompts collapse to the character module.
# Source after `starship init fish | source`.
function starship_transient_prompt_func
    starship module character $argv
end
enable_transience
