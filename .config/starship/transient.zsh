# Transient prompt for zsh. Starship only supports this natively in fish and
# PowerShell, so redraw the prompt as just the character module once a line
# is accepted. Source after `starship init zsh`.
#
# recursive-edit (rather than zle-line-finish) lets Ctrl-C and Ctrl-D on an
# empty line collapse the prompt too.
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
    PROMPT='$(starship module character --status="${STARSHIP_CMD_STATUS:-}")'
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
