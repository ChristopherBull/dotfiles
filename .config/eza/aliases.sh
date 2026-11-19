# shellcheck shell=bash
# eza aliases for bash and zsh. Guarded so ls still works where eza is missing.
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --icons --git --group-directories-first'
    alias la='eza -la --icons --git --group-directories-first'
    alias lt='eza --tree --icons --level=2'
fi
