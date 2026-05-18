#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting dotfiles installation..."

# -----------------------------------------------------------------------------
# Symlink configs
# -----------------------------------------------------------------------------

link_file() {
    local source="$1"
    local target="$2"

    mkdir -p "$(dirname "$target")"
    ln -sf "$source" "$target"
}

# Example config links
# link_file "$DOTFILES_DIR/config/starship.toml" ~/.config/starship.toml
# link_file "$DOTFILES_DIR/config/gitconfig" ~/.gitconfig

# -----------------------------------------------------------------------------
# Zsh setup
# -----------------------------------------------------------------------------

echo "🐚 Checking Zsh installation..."

install_zsh() {
    echo "📦 Attempting to install Zsh..."

    if command -v brew >/dev/null 2>&1; then
        echo "➡️ Using Homebrew"
        brew install zsh

    elif command -v apt-get >/dev/null 2>&1; then
        echo "➡️ Using apt-get"
        sudo apt-get update
        sudo apt-get install -y zsh

    elif command -v dnf >/dev/null 2>&1; then
        echo "➡️ Using dnf"
        sudo dnf install -y zsh

    elif command -v yum >/dev/null 2>&1; then
        echo "➡️ Using yum"
        sudo yum install -y zsh

    elif command -v pacman >/dev/null 2>&1; then
        echo "➡️ Using pacman"
        sudo pacman -S --noconfirm zsh

    else
        echo "❌ No supported package manager found. Please install Zsh manually."
        return 1
    fi
}

if command -v zsh >/dev/null 2>&1; then
    echo "✅ Zsh is already installed: $(zsh --version)"
else
    echo "⚠️ Zsh not found"
    install_zsh
fi

ZSH_PATH="$(command -v zsh || true)"

if [[ -n "$ZSH_PATH" ]]; then
    echo "🔍 Found Zsh at: $ZSH_PATH"

    # Ensure Zsh is listed in /etc/shells (required for chsh on some systems)
    if [[ -f /etc/shells ]]; then
        if ! grep -qx "$ZSH_PATH" /etc/shells; then
            echo "➕ Adding Zsh to /etc/shells (may require sudo)..."
            echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    echo "🔄 Setting Zsh as default shell..."
    chsh -s "$ZSH_PATH" "$USER" || {
        echo "⚠️ Could not change default shell automatically. You may need to run:"
        echo "   chsh -s $ZSH_PATH"
    }

    echo "🧪 Verifying shell..."
    echo "Current shell: $SHELL"
else
    echo "❌ Zsh installation failed or path not found."
fi

# -----------------------------------------------------------------------------
# Starship
# -----------------------------------------------------------------------------

add_line_if_missing() {
    local line="$1"
    local file="$2"

    touch "$file"
    grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

echo "🔧 Configuring Starship..."

if command -v starship >/dev/null 2>&1; then
    # Detect shell (prefer current process shell)
    CURRENT_SHELL="$(basename "$(ps -p $$ -o comm=)")"

    echo "🧭 Detected shell: $CURRENT_SHELL"

    case "$CURRENT_SHELL" in
        bash)
            echo "➡️ Configuring Starship for Bash"
            add_line_if_missing 'eval "$(starship init bash)"' ~/.bashrc
            ;;

        zsh)
            echo "➡️ Configuring Starship for Zsh"
            add_line_if_missing 'eval "$(starship init zsh)"' ~/.zshrc
            ;;

        *)
            echo "⚠️ Unsupported or unknown shell: $CURRENT_SHELL"
            echo "➡️ Falling back to Bash + Zsh configuration"
            add_line_if_missing 'eval "$(starship init bash)"' ~/.bashrc
            add_line_if_missing 'eval "$(starship init zsh)"' ~/.zshrc
            ;;
    esac

    echo "✅ Starship configured"
else
    echo "⚠️ Starship not found. Please install Starship and re-run to enable prompt integration."
fi

# -----------------------------------------------------------------------------

echo "🎉 Dotfiles installation complete."