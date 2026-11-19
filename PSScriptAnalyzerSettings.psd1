# PSScriptAnalyzer settings for CI and local runs:
#   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
# The default rules, plus the compatibility rules checking every script still
# runs on Windows PowerShell 5.1 (the version Windows ships) as well as 7.
@{
    # ParseError too: without it a script that doesn't parse reports nothing.
    Severity = @('ParseError', 'Error', 'Warning', 'Information')
    Rules    = @{
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
        PSUseCompatibleTypes    = @{
            Enable         = $true
            TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
    }
}
