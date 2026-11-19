# dotfiles

[![Validate](https://github.com/ChristopherBull/dotfiles/actions/workflows/validate.yml/badge.svg)](https://github.com/ChristopherBull/dotfiles/actions/workflows/validate.yml)

Personal workspace and terminal configuration files. Sync my development environment preferences across different machines and Dev Containers. Maintains a consistent settings when working with disposable environments like Dev Containers.

Configure the environment, not provision it.

## Features

- Terminal customisations
- Editor configurations
- Development environment settings
- Cross-platform compatibility

## Installation

### For Dev Containers (Recommended)

Dev Container support is built-in for automatic environment setup. To apply to all workspaces and Dev Containers, add the following to the User `settings.json`:

```json
{
    "dotfiles.repository": "https://github.com/YOURNAME/dotfiles",
    "dotfiles.targetPath": "~/dotfiles",
    "dotfiles.installCommand": "install.sh"
}
```

### Manual Installation

1. Clone the repository:

    ```bash
    git clone https://github.com/YOURNAME/dotfiles.git ~/.dotfiles
    ```

2. Run the installation script:

    ```bash
    cd ~/.dotfiles && ./install.sh
    ```

    > [!NOTE]
    > Each section (zsh, `gh`, Starship, VS Code, etc.) fails independently — an
    > error in one won't stop the rest from installing.

    It runs non-interactively by default. Steps that need root (installing
    packages, changing the login shell) only run as root or through
    passwordless sudo, as in Dev Containers; otherwise they are skipped with a
    hint. Pass `--sudo` (or set `DOTFILES_SUDO=1`) to let sudo prompt for a
    password:

    ```bash
    ./install.sh --sudo
    ```

    It installs any missing zsh, `gh`, ShellCheck, `jq`, Starship, eza, a Nerd
    Font and Claude Code. Starship and Claude Code go into `~/.local/bin`, so
    they never need root.

## VS Code User Settings

This repository includes a sample VS Code user settings file at [`.config/.vscode/user.settings.json`](/.config/.vscode/user.settings.json). This file is **not** automatically installed, but provides a set of recommended settings that complement the dotfiles and can impact your development environment. These settings are not guaranteed to sync across all VS Code instances, so you may need to manually copy them into your own `settings.json` if you want them applied.

**Summary of included settings:**

- Dotfiles integration: repository URL, target path, and install command for Dev Containers
- Terminal and shell preferences for Linux (ensure to not override shell customisations)
- Default Dev Container features (e.g., Zsh, Starship prompt, Open Code)
- Default IDE extensions

> [!NOTE]
> Review and copy the contents of `.config/.vscode/user.settings.json` into your own VS Code user settings as needed.

> [!TIP]
> The typical base devcontainer image [`mcr.microsoft.com/devcontainers/base`](https://mcr.microsoft.com/en-us/artifact/mar/devcontainers/base/about) pre-installs common dependencies for development, including `zsh`. You can enable it in User `settings.json`:
>
> ```json
> "dev.containers.defaultFeatures": {
>    "ghcr.io/devcontainers/features/common-utils:2": {
>      "installZsh": true,
>      "configureZshAsDefaultShell": true
>    },
>  },
> ```

## Starship theme

[`.config/starship/starship.toml`](/.config/starship/starship.toml) is a
Powerlevel10k Classic-style theme made with
[starlevel10k](https://github.com/odt1/starlevel10k)'s
[configurator](https://odt1.github.io/starlevel10k/configure.html). The answers
are in its header, along with a link that opens the configurator with them
selected. Two changes from the generated file: the previous command's duration
shows from 1 second as `▲ 1m15s`, with a desktop notification after 45 seconds,
and the time is `HH:MM`. `install.sh` symlinks it to `~/.config/starship.toml`.

Other themes live in [`.config/starship/themes/`](/.config/starship/themes).
To try one in the current shell only:

```sh
export STARSHIP_CONFIG=~/dotfiles/.config/starship/themes/catppuccin-powerline.toml
```

## Transient prompt

Once a command is entered, its full Starship prompt collapses to just the `❯`
character, so scrollback stays compact. The snippets live in
[`.config/starship/`](/.config/starship):

- **fish** (`transient.fish`) uses Starship's built-in `enable_transience`.
- **zsh** (`transient.zsh`) is a `zle-line-init` widget, as Starship has no
  native zsh support.
- **PowerShell** (`transient.ps1`) uses Starship's `Enable-TransientPrompt`.
- **cmd** (`.config/clink/starship.lua`) uses Clink's `prompt.transient`.

`install.sh` sources the fish and zsh snippets after `starship init`. For
PowerShell and cmd, see [PowerShell (Windows)](#powershell-windows) and
[cmd](#cmd-windows-through-clink).

## File icons in `ls`

`install.sh` installs [eza](https://github.com/eza-community/eza), a fast `ls`
replacement, and sources aliases for bash, zsh
([`.config/eza/aliases.sh`](/.config/eza/aliases.sh)) and fish
([`.config/eza/aliases.fish`](/.config/eza/aliases.fish)):

| Alias | Runs |
| --- | --- |
| `ls` | `eza --icons --group-directories-first` |
| `ll` | `eza -l --icons --git --group-directories-first` |
| `la` | `eza -la --icons --git --group-directories-first` |
| `lt` | `eza --tree --icons --level=2` |

The aliases are only set when `eza` is on `PATH`, so `ls` keeps working where
it isn't installed.

### Nerd Font

The icons (and the Starship prompt) need a [Nerd Font](https://www.nerdfonts.com/).
`install.sh` installs FiraCode Nerd Font, the font the Ghostty config uses: with
pacman on Arch, Homebrew on macOS, and otherwise as a per-user download into
`~/.local/share/fonts`. It skips machines without fontconfig (likely headless).

Inside WSL or a Dev Container the terminal runs on the host, so a font installed
there would never be used. `install.sh` skips it and says so instead: install
the font on the host (e.g. `scoop bucket add nerd-fonts`, then
`scoop install FiraCode-NF` on Windows), then select it in your terminal and in
VS Code's `terminal.integrated.fontFamily`.

## PowerShell (Windows)

`install.sh` doesn't run on Windows, so set PowerShell up by hand.
[Terminal-Icons](https://github.com/devblackops/Terminal-Icons) is the
PowerShell counterpart to eza's icons. Install it once (it also needs a Nerd
Font):

```powershell
Install-Module -Name Terminal-Icons -Repository PSGallery
```

Starship's PowerShell setup leaves out `right_format`, so the theme's `─╯`
corner is missing. starlevel10k's `p10k-starship.ps1` adds it. It has no
licence, so it isn't copied into this repo; download it once:

```powershell
New-Item -ItemType Directory -Force "$HOME\p10k-starship" | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/odt1/starlevel10k/main/p10k-starship.ps1 `
    -OutFile "$HOME\p10k-starship\p10k-starship.ps1"
```

Then add these lines to your `$PROFILE` (open it with `notepad $PROFILE`, and
adjust the dotfiles path to wherever the repo is cloned). `p10k-starship.ps1`
must come straight after `starship init`, and the `if` keeps the profile
loading cleanly on a machine without Starship:

```powershell
Import-Module -Name Terminal-Icons
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
    . "$HOME\p10k-starship\p10k-starship.ps1"
    . "$HOME\dotfiles\.config\starship\transient.ps1"
}
```

## cmd (Windows, through Clink)

Starship runs in cmd through [Clink](https://chrisant996.github.io/clink/).
[`.config/clink/starship.lua`](/.config/clink/starship.lua) loads it with the
same transient prompt as the other shells. Register the folder and turn on
transience once (adjust the path to wherever the repo is cloned):

```bat
clink installscripts %USERPROFILE%\dotfiles\.config\clink
clink set prompt.transient always
```

## Global configurations

`install.sh` installs a small set of personal, user-scoped configs to your home
directory. Each is auto-discovered by its tool — no per-project wiring — so they
apply across all workspaces and Dev Containers. Project-level config always takes
precedence where it overlaps.

| Source | Installed to | Tool pickup |
| --- | --- | --- |
| [`.config/git/attributes`](/.config/git/attributes) | `~/.config/git/attributes` | Git's default global attributes path (no `git config` needed). |
| [`.config/claude/CLAUDE.md`](/.config/claude/CLAUDE.md) | `~/.claude/CLAUDE.md` | Claude Code user-scoped memory; layers under any repo `AGENTS.md`. |
| [`.config/claude/settings.json`](/.config/claude/settings.json) | `~/.claude/settings.json` | Claude Code global settings (allowlist, statusline). |
| [`.config/claude/statusline-command.sh`](/.config/claude/statusline-command.sh) | `~/.claude/statusline-command.sh` | Claude Code statusline, wired up by `settings.json`. |
| [`.config/claude/usage-gate.sh`](/.config/claude/usage-gate.sh) | `~/.claude/usage-gate.sh` | Exits non-zero when the 5-hour window is past a limit (default 80%), so long tasks don't start a new piece of work without enough left. |
| [`.config/claude/skills/*`](/.config/claude/skills) | `~/.claude/skills/*` | Claude Code personal skills, auto-discovered from the user skills dir. |

### Git attributes

Minimal, essential cross-platform line-ending safety only (Windows, macOS, and
Linux/Dev Containers): normalise to LF, force `*.sh`/`*.bash` to LF (CRLF breaks
shebangs in containers) and `*.bat`/`*.cmd` to CRLF. Symlinked, so edits
propagate. Per-repo `.gitattributes` still wins.

### Claude Code

- **`CLAUDE.md`** holds personal preferences only (e.g. British English, working
  style). It is symlinked and loads for every project, layering *under* a repo's
  tool-agnostic `AGENTS.md` — so no Claude-specific file is ever committed to a
  project repo.
- **`settings.json`** carries a conservative allowlist of named, predictable
  build/lint/test tools, plus the statusline hook. It is **merged** into any
  existing `~/.claude/settings.json` (array union) via `jq`, so local entries are
  preserved.
- **`statusline-command.sh`** renders the model, a context-window usage bar, and
  usage bars for the 5-hour and weekly rate limits with their reset times in UK
  time. It is symlinked, and `settings.json` invokes it via `$HOME` so the path
  holds on any machine. Needs `jq`; without it the statusline stays blank.
  Each refresh also writes the latest rate limits to
  `~/.claude/cache/rate-limits.json`, which `usage-gate.sh [max-percent]` reads.
- **`skills/`** holds personal Claude Code skills, one subfolder each. Every
  subfolder is symlinked individually into `~/.claude/skills/`, so unrelated
  skills already installed there are left untouched.
- **Auto-update in Dev Containers.** Features run as root, so a Claude Code
  feature added through `dev.containers.defaultFeatures` leaves its global npm
  package root-owned, and the auto-updater fails with "no write permission to
  npm prefix". In a Dev Container or Codespace, `install.sh` gives the package
  (`$(npm root -g)/@anthropic-ai`) to the remote user with `sudo chown`, so
  Claude Code can update itself while the feature's image layer stays cached.
  This needs passwordless sudo, or `--sudo`.

> [!NOTE]
> A global allowlist applies to **every** repo you open, including unfamiliar
> ones. The entries are limited to read-only commands and named tools, but
> dependency installs and test/build commands still execute repo-defined code.
> Scope anything you don't want auto-approved to a project's
> `.claude/settings.local.json` instead.

> [!TIP]
> A global cSpell config is deliberately **not** included. It would accept words
> locally that a repo's CI still flags (a local-dev vs reproducibility gap), so
> spelling conveniences belong in each repo's own `.cspell` config.

## Customisation

To customise for your environment:

1. Fork this repository
2. Modify configuration files as needed
3. Update the repository URL in your `settings.json`
