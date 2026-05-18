# dotfiles

Personal workspace and terminal configuration files. Sync my development environment preferences across different machines and Dev Containers. Maintains a consistent settings when working with disposable environments like Dev Containers.

Configure the environment, not provision it.

## Features

- Terminal customisations
- Editor configurations
- Development environment settings
- Cross-platform compatibility

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

## Installation

### For Dev Containers (Recommended)

Dev Container support is built-in for automatic environment setup. To apply to all workspaces and Dev Containers, add the following to the User `settings.json`:

```json
{
    "dotfiles.repository": "https://github.com/YOURNAME/dotfiles",
    "dotfiles.targetPath": "~",
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

## Customisation

To customise for your environment:

1. Fork this repository
2. Modify configuration files as needed
3. Update the repository URL in your `settings.json`
