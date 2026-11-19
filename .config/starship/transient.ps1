# Transient prompt for PowerShell: past prompts collapse to two blank lines
# (the add_newline gap, then one in place of the details bar) and the
# character module, so the prompt keeps its height.
# Dot-source from $PROFILE after `starship init powershell`.

# Enable-TransientPrompt comes from starship init, so skip without Starship.
if (-not (Get-Command starship -ErrorAction SilentlyContinue)) { return }

function Invoke-Starship-TransientFunction {
    # One string, not two pipeline items, so the prompt renders as written.
    "`n`n$(&starship module character)"
}
Enable-TransientPrompt
