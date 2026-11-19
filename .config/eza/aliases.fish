# eza aliases for fish. Guarded so ls still works where eza is missing.
if type -q eza
    alias ls 'eza --icons --group-directories-first'
    alias ll 'eza -l --icons --git --group-directories-first'
    alias la 'eza -la --icons --git --group-directories-first'
    alias lt 'eza --tree --icons --level=2'
end
