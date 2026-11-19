# Transient prompt for PowerShell: past prompts collapse to the character
# module. Dot-source from $PROFILE after `starship init powershell`.
function Invoke-Starship-TransientFunction {
    &starship module character
}
Enable-TransientPrompt
