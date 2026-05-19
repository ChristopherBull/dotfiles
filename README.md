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

## Customisation

To customise for your environment:

1. Fork this repository
2. Modify configuration files as needed
3. Update the repository URL in your `settings.json`
