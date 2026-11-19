# Transient prompt for zsh. Starship only supports this natively in fish and
# PowerShell, so redraw the prompt as two blank lines and the character module
# once a line is accepted. Source after `starship init zsh`.
#
# recursive-edit (rather than zle-line-finish) lets Ctrl-C and Ctrl-D on an
# empty line collapse the prompt too.

# zsh pads the right prompt one column from the edge by default, which leaves
# a gap after a right_format frame such as the p10k theme's "─╯".
ZLE_RPROMPT_INDENT=0

_starship_transient_line_init() {
    emulate -L zsh
    [[ $CONTEXT == start ]] || return 0

    local -i ret
    while true; do
        zle .recursive-edit
        ret=$?
        [[ $ret == 0 && $KEYS == $'\4' ]] || break
        [[ -o ignore_eof ]] || exit 0
    done

    local saved_prompt=$PROMPT saved_rprompt=$RPROMPT
    # Two newlines: add_newline's gap, then one in place of the details bar, so
    # the prompt keeps its height and nothing below it jumps.
    PROMPT=$'\n\n''$(starship module character --status="${STARSHIP_CMD_STATUS:-0}" --keymap="${KEYMAP:-}")'
    RPROMPT=''
    zle .reset-prompt
    PROMPT=$saved_prompt
    RPROMPT=$saved_rprompt

    if (( ret )); then
        zle .send-break
    else
        zle .accept-line
    fi
    return ret
}
zle -N zle-line-init _starship_transient_line_init
