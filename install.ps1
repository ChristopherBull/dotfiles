#Requires -Version 5.1
<#
.SYNOPSIS
    Windows counterpart to install.sh, which stays the source of truth.

.DESCRIPTION
    Installs and configures the same things as install.sh where they apply to
    Windows: CLI tools, Starship and its theme, a Nerd Font, icons in ls, the
    PowerShell profile, Clink, OpenCode, VS Code, Git and Claude Code. Sections
    that only make sense on Linux or in a Dev Container are listed at the end.

    Needs no admin rights, so it works on managed machines: winget installs
    with --scope user, fonts install per user and modules go to CurrentUser.
    Windows symlinks need admin or Developer Mode, so files install.sh
    symlinks are copied instead (re-run to refresh them) and skill folders
    are linked with directory junctions, which need neither.

    Safe to re-run. Each section fails independently. Run it from the clone,
    bypassing the execution policy for this process only:

        powershell -ExecutionPolicy Bypass -File .\install.ps1

    Kept to ASCII on purpose: Windows PowerShell 5.1 reads BOM-less scripts as
    ANSI, which would mangle anything else. Status icons are built from code
    points at runtime instead.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive installer: progress goes to the console, like echo in install.sh')]
param()

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest's progress bar slows downloads to a crawl in 5.1.
$ProgressPreference = 'SilentlyContinue'
# 5.1 can default to TLS 1.0, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$DotfilesDir = $PSScriptRoot
$UserBin = Join-Path $HOME '.local\bin'  # where Claude Code's installer puts claude.exe
$NerdFontFamily = 'FiraCode Nerd Font'  # matches .config/ghostty/config.ghostty
$P10kScript = Join-Path $HOME 'p10k-starship\p10k-starship.ps1'
$BlockStart = '# >>> dotfiles (managed by install.ps1; edits inside are overwritten) >>>'
$BlockEnd = '# <<< dotfiles <<<'

# Keep in sync with JQ_DEEPMERGE in install.sh: objects merge recursively
# (dotfiles wins on conflict) and arrays are unioned.
$JqDeepMerge = @'
def deepmerge($a; $b):
    if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $key (
            $a;
            . + { ($key): deepmerge($a[$key]; $b[$key]) }
        )
    elif ($a | type) == "array" and ($b | type) == "array" then
        ($a + $b | unique)
    elif $b == null then $a
    else $b
    end;
deepmerge(.[0]; .[1])
'@

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# The same icons as install.sh, built at runtime to keep this file ASCII.
$IconOk = [char]::ConvertFromUtf32(0x2705)
$IconWarn = [char]::ConvertFromUtf32(0x2757)
$IconSkip = [char]::ConvertFromUtf32(0x23E9)
$IconHint = [char]::ConvertFromUtf32(0x1F449)
$IconTodo = [char]::ConvertFromUtf32(0x26A0) + [char]::ConvertFromUtf32(0xFE0F)

function Write-Section([string]$Title) { Write-Host ''; Write-Host $Title }
function Write-Info([string]$Label, [string]$Message) { Write-Host "  ...[$Label] $Message" }
function Write-Ok([string]$Label, [string]$Message) { Write-Host "  $IconOk [$Label] $Message" }
function Write-Skip([string]$Label, [string]$Message) { Write-Host "  $IconSkip [$Label] $Message" }
function Write-Warn([string]$Label, [string]$Message) { Write-Host "  $IconWarn [$Label] $Message" -ForegroundColor Yellow }
function Write-Hint([string]$Label, [string]$Message) { Write-Host "  $IconHint [$Label] $Message" }
# A known gap: something install.sh does that this script can't (yet).
function Write-Todo([string]$Label, [string]$Message) { Write-Host "  $IconTodo [$Label] TODO: $Message" -ForegroundColor Yellow }

function Invoke-Section([string]$Label, [scriptblock]$Body) {
    try { & $Body }
    catch { Write-Warn $Label "Section encountered an error: $($_.Exception.Message); continuing with the rest of the install" }
}

function Test-Command([string]$Name) {
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Installs add to the user PATH, which this session doesn't see until it
# re-reads it.
function Sync-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Appends $Dir to the user PATH. Read and written through the registry
# unexpanded, so entries such as %USERPROFILE%\bin survive.
function Add-UserPath([string]$Dir) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $current = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($current -split ';' | Where-Object { $_ })
        $expanded = @($entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
        if ($expanded -contains $Dir.TrimEnd('\')) { return $false }
        $key.SetValue('Path', ((@($entries) + $Dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        $key.Close()
    }
    Sync-SessionPath
    return $true
}

# Installs a winget package for the current user unless $Command already
# exists. Returns whether $Command is available afterwards.
function Install-WingetPackage([string]$Label, [string]$Id, [string]$Command) {
    if (Test-Command $Command) {
        Write-Ok $Label "Already installed: $((& $Command --version 2>&1 | Select-Object -First 1))"
        return $true
    }
    if (-not (Test-Command winget)) {
        Write-Warn $Label 'winget not found; install App Installer from the Microsoft Store'
        return $false
    }
    Write-Info $Label "Installing $Id with winget (user scope, no admin)"
    # Out-Host keeps winget's output out of this function's return value.
    & winget install --id $Id --exact --scope user --silent `
        --accept-source-agreements --accept-package-agreements | Out-Host
    $exitCode = $LASTEXITCODE
    Sync-SessionPath
    if (Test-Command $Command) {
        Write-Ok $Label 'Installed'
        return $true
    }
    if ($exitCode -ne 0) { Write-Warn $Label "winget failed (exit $exitCode); see its output above" }
    else { Write-Warn $Label 'Installed but not on PATH yet; open a new terminal and re-run' }
    return $false
}

# Copies $Source over $Target when they differ. Stands in for install.sh's
# symlinks, so edits in the repo reach $Target on the next run.
function Copy-IfChanged([string]$Label, [string]$Source, [string]$Target) {
    if (-not (Test-Path $Source)) {
        Write-Warn $Label "Missing source: $Source; skipping"
        return
    }
    if ((Test-Path $Target) -and
        (Get-FileHash $Source).Hash -eq (Get-FileHash $Target).Hash) {
        Write-Ok $Label "Up to date: $Target"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
    Copy-Item -Path $Source -Destination $Target -Force
    Write-Ok $Label "Copied to $Target"
}

# Runs jq with $Program read from a file: Windows PowerShell 5.1 mangles
# double quotes in arguments to native programs. Returns the output, or
# $null on failure.
function Invoke-Jq([string]$Program, [string[]]$Arguments) {
    $programFile = [IO.Path]::GetTempFileName()
    $previousEncoding = [Console]::OutputEncoding
    try {
        [IO.File]::WriteAllText($programFile, $Program)
        # jq writes UTF-8; without this, PowerShell decodes it as the OEM code page.
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $output = & jq -f $programFile @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($output -join "`n") + "`n"
    } finally {
        [Console]::OutputEncoding = $previousEncoding
        Remove-Item -Force $programFile -ErrorAction SilentlyContinue
    }
}

# Writes UTF-8 without a BOM, through a temp file so a failure can't leave
# $Target half-written.
function Write-FileAtomic([string]$Target, [string]$Content) {
    $tmp = "$Target.tmp"
    [IO.File]::WriteAllText($tmp, $Content, (New-Object Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $Target -Force
}

# Copies $Source to $Target, or deep-merges it into an existing $Target with
# jq, as install.sh does for VS Code and Claude Code settings.
function Merge-JsonSetting([string]$Label, [string]$Source, [string]$Target) {
    if (-not (Test-Path $Source)) {
        Write-Warn $Label "Missing source: $Source; skipping"
        return
    }
    if (-not (Test-Path $Target)) {
        Write-Info $Label 'No existing settings found; copying dotfiles settings'
        New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
        Copy-Item -Path $Source -Destination $Target
        Write-Ok $Label 'Settings applied'
        return
    }
    if (-not (Test-Command jq)) {
        Write-Warn $Label 'jq not installed; cannot merge into existing settings'
        Write-Info $Label 'Skipping (install jq and re-run to apply)'
        return
    }
    Write-Info $Label "Existing settings found at $Target; merging"
    $merged = Invoke-Jq $JqDeepMerge @('-s', $Target, $Source)
    if (-not $merged) {
        # Same limitation as install.sh: jq can't read comments or trailing commas.
        Write-Warn $Label 'jq merge failed (comments or trailing commas in the file?); skipping'
        return
    }
    Write-FileAtomic $Target $merged
    Write-Ok $Label 'Settings merged'
}

Write-Host ''
Write-Host 'Starting dotfiles installation (Windows)'

# Everything installs per user, so admin is never needed. Elevated, it
# would install into the admin account's profile, which on a managed machine
# is often a different user.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ((New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warn 'admin' "Running as administrator ($($identity.Name)); per-user installs go to that account. Re-run from a normal terminal"
}

# -ExecutionPolicy Bypass can't override a policy set by Group Policy, and
# changing that needs admin. AllSigned or Restricted would stop the profile
# from loading this repo's unsigned scripts.
foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
    $policy = Get-ExecutionPolicy -Scope $scope
    if ($policy -in @('AllSigned', 'Restricted')) {
        # TODO: sign transient.ps1 and p10k-starship.ps1, or inline them into
        # the profile, for machines whose Group Policy requires AllSigned.
        Write-Todo 'policy' "Group Policy sets the execution policy to $policy ($scope); the profile can't load unsigned scripts"
    }
}

# Device Guard / AppLocker policies on managed machines can force Constrained
# Language Mode, which blocks the .NET calls below.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Todo 'shell' "PowerShell is in $($ExecutionContext.SessionState.LanguageMode) mode, so several sections will fail; support for it isn't built yet"
}

# -----------------------------------------------------------------------------
# User bin (~\.local\bin on PATH; install.sh's section_local_bin)
# -----------------------------------------------------------------------------

Write-Section 'User bin'
Invoke-Section 'bin' {
    New-Item -ItemType Directory -Force -Path $UserBin | Out-Null
    if (Add-UserPath $UserBin) { Write-Ok 'bin' "Added $UserBin to the user PATH" }
    else { Write-Ok 'bin' "$UserBin already on the user PATH" }
    # install.sh also links .local/bin's scripts; both are Linux-only (a
    # Dev Container gh credential wrapper and a desktop display toggle).
    Write-Skip 'bin' 'Scripts in .local/bin are Linux-only; not installed'
}

# -----------------------------------------------------------------------------
# CLI tools: gh, ShellCheck, jq
# -----------------------------------------------------------------------------

Write-Section 'GitHub CLI (gh)'
Invoke-Section 'gh' {
    if (Test-Command gh) {
        Write-Ok 'gh' "Already installed: $((& gh --version | Select-Object -First 1))"
        return
    }
    # Not winget: gh's package is an MSI that can ask for admin. The portable
    # zip from its latest release never does.
    Write-Info 'gh' 'Installing the portable release from GitHub (no admin)'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $release = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/cli/cli/releases/latest'
    $asset = $release.assets | Where-Object { $_.name -like "*_windows_$arch.zip" } | Select-Object -First 1
    if (-not $asset) {
        Write-Warn 'gh' "No windows_$arch zip in release $($release.tag_name); install gh from https://cli.github.com"
        return
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('gh-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp $asset.name
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $tmp
        $exe = Get-ChildItem -Path $tmp -Recurse -Filter 'gh.exe' | Select-Object -First 1
        Copy-Item -Path $exe.FullName -Destination (Join-Path $UserBin 'gh.exe') -Force
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    Sync-SessionPath
    if (Test-Command gh) { Write-Ok 'gh' "Installed $($release.tag_name) to $UserBin" }
    else { Write-Warn 'gh' "Copied to $UserBin but not on PATH; open a new terminal" }
}

Write-Section 'ShellCheck'
Invoke-Section 'shellcheck' { Install-WingetPackage -Label 'shellcheck' -Id 'koalaman.shellcheck' -Command 'shellcheck' | Out-Null }

Write-Section 'jq (used below to merge JSON configs, and by the Claude Code statusline)'
Invoke-Section 'jq' { Install-WingetPackage -Label 'jq' -Id 'jqlang.jq' -Command 'jq' | Out-Null }

# -----------------------------------------------------------------------------
# Starship
# -----------------------------------------------------------------------------

Write-Section 'Starship configuration'
Invoke-Section 'starship' {
    if (-not (Install-WingetPackage -Label 'starship' -Id 'Starship.Starship' -Command 'starship')) { return }

    # A user variable stands in for install.sh's symlink to
    # ~/.config/starship.toml, and reaches cmd and Clink as well.
    $config = Join-Path $DotfilesDir '.config\starship\starship.toml'
    if (-not (Test-Path $config)) {
        Write-Warn 'starship' "Missing source config: $config; skipping"
    } elseif ([Environment]::GetEnvironmentVariable('STARSHIP_CONFIG', 'User') -eq $config) {
        Write-Ok 'starship' "STARSHIP_CONFIG already points at $config"
    } else {
        [Environment]::SetEnvironmentVariable('STARSHIP_CONFIG', $config, 'User')
        $env:STARSHIP_CONFIG = $config
        Write-Ok 'starship' "STARSHIP_CONFIG set to $config"
    }
}

# -----------------------------------------------------------------------------
# Nerd Font (per user: no admin)
# -----------------------------------------------------------------------------

Write-Section 'Nerd Font'
Invoke-Section 'font' {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

    $registered = @()
    if (Test-Path $regPath) {
        $registered = (Get-ItemProperty $regPath).PSObject.Properties.Name
    }
    if ($registered -like 'FiraCodeNerdFont*') {
        Write-Ok 'font' "$NerdFontFamily already installed"
        return
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('nerd-font-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Info 'font' "Downloading $NerdFontFamily"
        $zip = Join-Path $tmp 'FiraCode.zip'
        Invoke-WebRequest -UseBasicParsing -OutFile $zip `
            -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip'
        Expand-Archive -Path $zip -DestinationPath $tmp

        # Per-user fonts (Windows 10 1809+) live in LOCALAPPDATA and are
        # registered under HKCU; the value name is only a label.
        New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        foreach ($font in Get-ChildItem -Path $tmp -Filter '*.ttf') {
            $dest = Join-Path $fontDir $font.Name
            Copy-Item -Path $font.FullName -Destination $dest -Force
            New-ItemProperty -Path $regPath -Name "$($font.BaseName) (TrueType)" `
                -Value $dest -PropertyType String -Force | Out-Null
        }
        Write-Ok 'font' "$NerdFontFamily installed for $env:USERNAME"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    Write-Hint 'font' "Restart Windows Terminal, then pick '$NerdFontFamily' in its profile's Appearance settings"
    Write-Hint 'font' "For VS Code, set terminal.integrated.fontFamily to '$NerdFontFamily'"
}

# -----------------------------------------------------------------------------
# Terminal-Icons (icons in ls; install.sh uses eza)
# -----------------------------------------------------------------------------

Write-Section 'Terminal-Icons'
Invoke-Section 'icons' {
    if (Get-Module -ListAvailable -Name Terminal-Icons) {
        Write-Ok 'icons' 'Already installed'
    } else {
        Write-Info 'icons' 'Installing from PSGallery (CurrentUser)'
        # Windows PowerShell 5.1 needs the NuGet provider first. Installed
        # explicitly for the current user: the implicit bootstrap may target
        # all users, which needs admin.
        if ($PSVersionTable.PSVersion.Major -lt 6 -and
            -not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        }
        # -Force skips the untrusted-repository prompt.
        Install-Module -Name Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force
        Write-Ok 'icons' 'Installed'
    }
}

# -----------------------------------------------------------------------------
# p10k-starship.ps1 (the theme's right-hand frame in PowerShell)
# -----------------------------------------------------------------------------

Write-Section 'p10k-starship.ps1'
Invoke-Section 'p10k' {
    # Downloaded rather than vendored: upstream has no licence.
    if (Test-Path $P10kScript) {
        Write-Ok 'p10k' "Already at $P10kScript"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $P10kScript) | Out-Null
        Invoke-WebRequest -UseBasicParsing -OutFile $P10kScript `
            -Uri 'https://raw.githubusercontent.com/odt1/starlevel10k/main/p10k-starship.ps1'
        Write-Ok 'p10k' "Downloaded to $P10kScript"
    }
}

# -----------------------------------------------------------------------------
# PowerShell profiles (install.sh's rc-file lines)
# -----------------------------------------------------------------------------

Write-Section 'PowerShell profile'
Invoke-Section 'profile' {
    # A clone downloaded as a zip carries Mark-of-the-Web, which RemoteSigned
    # refuses to dot-source.
    $transient = Join-Path $DotfilesDir '.config\starship\transient.ps1'
    foreach ($script in @($transient, $P10kScript)) {
        if (Test-Path $script) { Unblock-File -Path $script }
    }

    # Doubled quotes keep a path such as C:\Users\O'Brien valid inside '...'.
    $p10kQuoted = $P10kScript -replace "'", "''"
    $transientQuoted = $transient -replace "'", "''"
    $block = @(
        $BlockStart
        "if (Get-Module -ListAvailable -Name Terminal-Icons) { Import-Module -Name Terminal-Icons }"
        "if (Get-Command starship -ErrorAction SilentlyContinue) {"
        "    Invoke-Expression (&starship init powershell)"
        "    if (Test-Path '$p10kQuoted') { . '$p10kQuoted' }"
        "    . '$transientQuoted'"
        "}"
        $BlockEnd
    ) -join [Environment]::NewLine

    # Windows PowerShell 5.1 and PowerShell 7 keep separate profiles. MyDocuments
    # follows OneDrive folder redirection, which managed machines often use.
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    if ((Test-Command pwsh) -or $PSVersionTable.PSVersion.Major -ge 7) {
        $profiles += Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }

    foreach ($path in $profiles) {
        $text = ''
        if (Test-Path $path) { $text = [IO.File]::ReadAllText($path) }

        # Drop the old block, then any hand-added init line it replaces, so
        # Starship isn't initialised twice.
        $pattern = '(?s)\r?\n?' + [regex]::Escape($BlockStart) + '.*?' + [regex]::Escape($BlockEnd)
        $kept = [regex]::Replace($text, $pattern, '')
        $lines = $kept -split '\r?\n'
        $initLine = 'Invoke-Expression (&starship init powershell)'
        $removed = @($lines | Where-Object { $_.Trim() -eq $initLine }).Count
        $lines = @($lines | Where-Object { $_.Trim() -ne $initLine })
        $body = ($lines -join [Environment]::NewLine).TrimEnd()

        $new = if ($body) { $body + [Environment]::NewLine + [Environment]::NewLine + $block } else { $block }
        $new += [Environment]::NewLine

        if ($new -eq $text) {
            Write-Ok 'profile' "Already up to date: $path"
            continue
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        # UTF-8 with a BOM, so 5.1 reads any non-ASCII already in the profile.
        [IO.File]::WriteAllText($path, $new, (New-Object Text.UTF8Encoding($true)))
        Write-Ok 'profile' "Configured $path"
        if ($removed) {
            Write-Ok 'profile' "Removed $removed hand-added Starship init line(s); the managed block does it"
        }
    }
}

# -----------------------------------------------------------------------------
# Clink (Starship in cmd), only if Clink is installed
# -----------------------------------------------------------------------------

Write-Section 'Clink'
Invoke-Section 'clink' {
    if (-not (Test-Command clink)) {
        Write-Skip 'clink' 'Not installed; skipping cmd setup'
        return
    }
    & clink installscripts (Join-Path $DotfilesDir '.config\clink') | Out-Null
    & clink set prompt.transient always | Out-Null
    Write-Ok 'clink' 'Registered .config\clink and turned on the transient prompt'
}

# -----------------------------------------------------------------------------
# OpenCode config
# -----------------------------------------------------------------------------

Write-Section 'OpenCode configuration'
Invoke-Section 'opencode' {
    if (-not (Test-Command opencode)) {
        Write-Skip 'opencode' 'Not installed; skipping'
        return
    }
    Write-Info 'opencode' 'Detected'

    $source = Join-Path $DotfilesDir '.config\opencode\opencode.json'
    # TODO: confirm OpenCode reads ~\.config\opencode on native Windows, as on
    # Linux and macOS; its docs only give the XDG path.
    $target = Join-Path $HOME '.config\opencode\opencode.json'
    Write-Todo 'opencode' "Confirm OpenCode on Windows reads $target"

    if (-not (Test-Path $source)) {
        Write-Warn 'opencode' "Missing source config: $source"
        Write-Info 'opencode' 'Skipping hydration'
        return
    }
    if (Test-Path $target) {
        Write-Ok 'opencode' 'Config already exists; skipping (delete to re-hydrate)'
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null

    if (-not $env:OLLAMA_BASE_URL) {
        Write-Info 'opencode' 'OLLAMA_BASE_URL not set; copying default config'
        Copy-Item -Path $source -Destination $target
    } elseif (-not (Test-Command jq)) {
        Write-Warn 'opencode' 'jq not installed; cannot apply baseURL override'
        Write-Info 'opencode' 'Copying default config without URL override'
        Copy-Item -Path $source -Destination $target
    } else {
        Write-Info 'opencode' "OLLAMA_BASE_URL=$env:OLLAMA_BASE_URL"
        $result = Invoke-Jq '.provider.ollama.options.baseURL = $url' @('--arg', 'url', $env:OLLAMA_BASE_URL, $source)
        if ($result) {
            Write-FileAtomic $target $result
            Write-Info 'opencode' 'baseURL override applied'
        } else {
            Write-Warn 'opencode' 'jq failed; copying default config'
            Copy-Item -Path $source -Destination $target
        }
    }
    Write-Ok 'opencode' 'Config written'
}

# -----------------------------------------------------------------------------
# VS Code user settings
# -----------------------------------------------------------------------------

Write-Section 'VS Code configuration'
Invoke-Section 'vscode' {
    if (-not (Test-Command code)) {
        Write-Skip 'vscode' 'Not installed; skipping'
        return
    }
    Write-Info 'vscode' "Detected: $((& code --version 2>$null | Select-Object -First 1))"
    Merge-JsonSetting -Label 'vscode' -Source (Join-Path $DotfilesDir '.config\.vscode\user.settings.json') -Target (Join-Path $env:APPDATA 'Code\User\settings.json')
}

# -----------------------------------------------------------------------------
# Global Git attributes
# -----------------------------------------------------------------------------

Write-Section 'Global Git attributes'
Invoke-Section 'git' {
    # ~\.config\git\attributes is Git's default global attributes path on
    # Windows too (no git config needed). Copied, not linked: see the header.
    Copy-IfChanged -Label 'git' -Source (Join-Path $DotfilesDir '.config\git\attributes') -Target (Join-Path $HOME '.config\git\attributes')
}

# -----------------------------------------------------------------------------
# Git identity
# -----------------------------------------------------------------------------

Write-Section 'Git identity'
Invoke-Section 'git' {
    if (-not (Test-Command git)) {
        Write-Skip 'git' 'Not installed; skipping'
        Write-Hint 'git' 'Claude Code on Windows needs Git for Windows: winget install --id Git.Git --exact --scope user'
        Write-Hint 'git' 'If that asks for admin, use PortableGit from https://git-scm.com/download/win (no install needed)'
        return
    }
    # Only warn: the identity is personal, so it isn't kept in the dotfiles.
    $missing = $false
    foreach ($key in @('user.name', 'user.email')) {
        $value = & git config --get $key
        if ($value) { Write-Ok 'git' "${key}: $value" }
        else {
            Write-Warn 'git' "$key not set; commits will fail until it is"
            $missing = $true
        }
    }
    if ($missing) {
        Write-Hint 'git' 'Run: git config --global user.name "Your Name"; git config --global user.email "you@example.com"'
    }
}

# -----------------------------------------------------------------------------
# Claude Code install
# -----------------------------------------------------------------------------

Write-Section 'Claude Code install'
Invoke-Section 'claude' {
    if (Test-Command claude) {
        Write-Ok 'claude' "Already installed: $((& claude --version | Select-Object -First 1))"
        return
    }
    Write-Info 'claude' 'Not found; running the native installer'
    # The official Windows installer, run in its own scope so its variables
    # can't clash with this script's. It installs to ~\.local\bin.
    & ([scriptblock]::Create((Invoke-RestMethod -UseBasicParsing -Uri 'https://claude.ai/install.ps1')))
    Sync-SessionPath
    if (Test-Command claude) { Write-Ok 'claude' "Installed: $((& claude --version | Select-Object -First 1))" }
    else { Write-Warn 'claude' "Installer finished but claude isn't on PATH; open a new terminal" }
}

# -----------------------------------------------------------------------------
# Global Claude Code settings
# -----------------------------------------------------------------------------

Write-Section 'Global Claude Code settings'
Invoke-Section 'claude' {
    $claudeDir = Join-Path $HOME '.claude'
    $source = Join-Path $DotfilesDir '.config\claude'

    # Personal CLAUDE.md (user-scoped memory). Copied, not linked: see the header.
    Copy-IfChanged -Label 'claude' -Source (Join-Path $source 'CLAUDE.md') -Target (Join-Path $claudeDir 'CLAUDE.md')

    # Statusline script and the usage gate that reads its rate-limit cache.
    Copy-IfChanged -Label 'claude' -Source (Join-Path $source 'statusline-command.sh') -Target (Join-Path $claudeDir 'statusline-command.sh')
    Copy-IfChanged -Label 'claude' -Source (Join-Path $source 'usage-gate.sh') -Target (Join-Path $claudeDir 'usage-gate.sh')
    # TODO: check the statusline renders under native Windows Claude Code.
    # settings.json runs it as `bash "$HOME/.claude/statusline-command.sh"`,
    # which needs Git for Windows' bash and jq on PATH; it is untested there
    # and may need a PowerShell port.
    Write-Todo 'claude' 'Statusline is untested on native Windows (runs through bash; needs Git for Windows and jq)'
    if (-not (Test-Command jq)) {
        Write-Warn 'claude' 'jq not installed; the statusline will stay blank until it is'
    }

    # Global settings.json (allowlist; merged to preserve existing).
    Merge-JsonSetting -Label 'claude' -Source (Join-Path $source 'settings.json') -Target (Join-Path $claudeDir 'settings.json')
}

# -----------------------------------------------------------------------------
# Claude Code personal skills
# -----------------------------------------------------------------------------

Write-Section 'Claude Code skills'
Invoke-Section 'skills' {
    $sourceDir = Join-Path $DotfilesDir '.config\claude\skills'
    $targetDir = Join-Path $HOME '.claude\skills'
    if (-not (Test-Path $sourceDir)) {
        Write-Warn 'skills' "Missing source dir: $sourceDir; skipping"
        return
    }
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    # One junction per skill rather than one for the whole folder, since
    # $targetDir may already hold skills from elsewhere. Junctions need no
    # admin and, like install.sh's symlinks, follow edits in the repo.
    foreach ($skill in Get-ChildItem -Path $sourceDir -Directory) {
        $target = Join-Path $targetDir $skill.Name
        if (Test-Path $target) {
            $existing = Get-Item -Force $target
            if ($existing.LinkType -ne 'Junction') {
                Write-Warn 'skills' "$($skill.Name) already exists and isn't a junction; skipping"
                continue
            }
            if (@($existing.Target) -contains $skill.FullName) {
                Write-Ok 'skills' "Already linked $($skill.Name)"
                continue
            }
            # DirectoryInfo.Delete() on a junction removes only the link;
            # Remove-Item can recurse into the folder it points at.
            $existing.Delete()
        }
        New-Item -ItemType Junction -Path $target -Target $skill.FullName | Out-Null
        Write-Ok 'skills' "Linked $($skill.Name)"
    }
}

# -----------------------------------------------------------------------------
# Not ported: install.sh sections that don't apply here, or not yet
# -----------------------------------------------------------------------------

Write-Section 'Not ported from install.sh'
Invoke-Section 'n/a' {
    # Linux-only: zsh as the login shell, Ghostty's config, the
    # minimal-shell host list, and Claude Code's npm ownership fix, which
    # only applies inside Dev Containers.
    Write-Skip 'n/a' 'zsh, Ghostty, minimal-shell hosts and the Dev Container Claude fix are Linux-only'

    # TODO: port section_lsp. It picks LSP plugins from the project in
    # /workspaces, which only exists in a Dev Container; on Windows there is
    # no project to inspect at install time.
    Write-Todo 'lsp' 'Language LSP plugins are not set up; install.sh derives them from a Dev Container project'
}

Write-Host ''
Write-Host 'Done. Open a new terminal to pick up the changes.'
