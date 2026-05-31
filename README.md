# dotfiles

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

## Global configurations

`install.sh` installs a small set of personal, user-scoped configs to your home
directory. Each is auto-discovered by its tool — no per-project wiring — so they
apply across all workspaces and Dev Containers. Project-level config always takes
precedence where it overlaps.

| Source | Installed to | Tool pickup |
| --- | --- | --- |
| [`.config/git/attributes`](/.config/git/attributes) | `~/.config/git/attributes` | Git's default global attributes path (no `git config` needed). |
| [`.config/claude/CLAUDE.md`](/.config/claude/CLAUDE.md) | `~/.claude/CLAUDE.md` | Claude Code user-scoped memory; layers under any repo `AGENTS.md`. |
| [`.config/claude/settings.json`](/.config/claude/settings.json) | `~/.claude/settings.json` | Claude Code global settings (allowlist). |

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
  build/lint/test tools. It is **merged** into any existing `~/.claude/settings.json`
  (array union) via `jq`, so local entries are preserved.

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
