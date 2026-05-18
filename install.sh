#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------

echo ""
echo "🚀 Starting dotfiles installation"

# -----------------------------------------------------------------------------
# Symlink configs
# -----------------------------------------------------------------------------

# echo "[core] Preparing symlink utilities"

# link_file() {
#     local source="$1"
#     local target="$2"

#     mkdir -p "$(dirname "$target")"
#     ln -sf "$source" "$target"
# }

# Example config links
# link_file "$DOTFILES_DIR/config/starship.toml" ~/.config/starship.toml
# link_file "$DOTFILES_DIR/config/gitconfig" ~/.gitconfig

# -----------------------------------------------------------------------------
# Zsh setup
# -----------------------------------------------------------------------------

echo ""
echo "🐚 Zsh setup"

install_zsh() {
    echo "...[zsh] Attempting installation"

    if command -v brew >/dev/null 2>&1; then
        echo "...[zsh] Using Homebrew"
        brew install zsh

    elif command -v apt-get >/dev/null 2>&1; then
        echo "...[zsh] Using apt-get"
        sudo apt-get update
        sudo apt-get install -y zsh

    elif command -v dnf >/dev/null 2>&1; then
        echo "...[zsh] Using dnf"
        sudo dnf install -y zsh

    elif command -v yum >/dev/null 2>&1; then
        echo "...[zsh] Using yum"
        sudo yum install -y zsh

    elif command -v pacman >/dev/null 2>&1; then
        echo "...[zsh] Using pacman"
        sudo pacman -S --noconfirm zsh

    else
        echo "❌ [zsh] No supported package manager found"
        return 1
    fi

    echo "✅ [zsh] Installed"
}

if command -v zsh >/dev/null 2>&1; then
    echo "✅ [zsh] Already installed: $(zsh --version)"
else
    echo "...[zsh] Not found"
    install_zsh
fi

echo ""
echo "🔄 Checking default login shell"

ZSH_PATH="$(command -v zsh || true)"

if [[ -n "$ZSH_PATH" ]]; then
    echo "...[shell] Found at $ZSH_PATH"

    if [[ -f /etc/shells ]]; then
        if ! grep -qx "$ZSH_PATH" /etc/shells; then
            echo "...[shell] Adding Zsh to /etc/shells"
            echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    if [[ -n "${container:-}" ]] || grep -qE 'docker|lxc|container' /proc/1/cgroup 2>/dev/null; then
        echo "🐳 [container] Detected container environment"
        echo "...[container] Skipping chsh (not appropriate in containers)"
        echo "...[container] Use container config to set shell if needed"
    else
        CURRENT_LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

        RESOLVED_CURRENT="$(readlink -f "$CURRENT_LOGIN_SHELL" 2>/dev/null || echo "$CURRENT_LOGIN_SHELL")"
        RESOLVED_ZSH="$(readlink -f "$ZSH_PATH" 2>/dev/null || echo "$ZSH_PATH")"

        echo "...[shell] Current login shell: $CURRENT_LOGIN_SHELL (resolved: $RESOLVED_CURRENT)"
        echo "...[shell] Desired shell: $ZSH_PATH (resolved: $RESOLVED_ZSH)"

        if [[ "$RESOLVED_CURRENT" == "$RESOLVED_ZSH" ]]; then
            echo "✅ [shell] Zsh already set as default"
        else
            echo "...[shell] Updating default shell to Zsh"

            if [[ -f /etc/shells ]]; then
                if ! grep -qx "$ZSH_PATH" /etc/shells; then
                    echo "...[shell] Registering zsh in /etc/shells"
                    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
                fi
            fi

            chsh -s "$ZSH_PATH" "$USER" || {
                echo "⚠️ [shell] chsh failed"
                echo "👉 [shell] Run: chsh -s $ZSH_PATH"
            }

            echo "...[shell] Post-change shell: $(getent passwd "$USER" | cut -d: -f7)"
        fi
    fi
else
    echo "❌ [shell] Installation failed or binary not found"
fi

# -----------------------------------------------------------------------------
# Starship
# -----------------------------------------------------------------------------

echo ""
echo "🔧 Starship configuration"

add_line_if_missing() {
    local line="$1"
    local file="$2"

    touch "$file"
    grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

if command -v starship >/dev/null 2>&1; then

    LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
    RESOLVED_LOGIN_SHELL="$(basename "$LOGIN_SHELL")"

    echo "...[starship] Login shell: $LOGIN_SHELL"
    echo "...[starship] Using: $RESOLVED_LOGIN_SHELL"

    case "$RESOLVED_LOGIN_SHELL" in
        bash)
            echo "...[starship] Configuring bash integration"
            add_line_if_missing 'eval "$(starship init bash)"' ~/.bashrc
            ;;

        zsh)
            echo "...[starship] Configuring zsh integration"
            add_line_if_missing 'eval "$(starship init zsh)"' ~/.zshrc
            ;;

        *)
            echo "⚠️ [starship] Unknown shell: $RESOLVED_LOGIN_SHELL"
            echo "...[starship] Falling back to bash + zsh config"
            add_line_if_missing 'eval "$(starship init bash)"' ~/.bashrc
            add_line_if_missing 'eval "$(starship init zsh)"' ~/.zshrc
            ;;
    esac

    # Starship theme
    STARSHIP_PRESET="${STARSHIP_PRESET:-no-runtime-versions}"
    echo "...[starship] Configuring starship theme - preset: $STARSHIP_PRESET"
    starship preset "$STARSHIP_PRESET" -o ~/.config/starship.toml

    echo "✅ [starship] Configured"
else
    echo "⚠️ [starship] Not installed"
fi

# -----------------------------------------------------------------------------
# OpenCode config
# -----------------------------------------------------------------------------

echo ""
echo "🛠️ OpenCode configuration"

if ! command -v opencode >/dev/null 2>&1; then
    echo "⏭️ [opencode] Not installed; skipping"
else
    echo "...[opencode] Detected"

    SOURCE_CONFIG="$DOTFILES_DIR/config/opencode/opencode.json"
    TARGET_DIR="$HOME/.config/opencode"
    TARGET_CONFIG="$TARGET_DIR/opencode.json"

    if [[ ! -f "$SOURCE_CONFIG" ]]; then
        echo "⚠️ [opencode] Missing source config: $SOURCE_CONFIG"
        echo "...[opencode] Skipping hydration"
    else
        mkdir -p "$TARGET_DIR"

        OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-}"

        if [[ -n "$OLLAMA_BASE_URL" ]]; then
            echo "...[opencode] OLLAMA_BASE_URL=$OLLAMA_BASE_URL"

            if ! command -v jq >/dev/null 2>&1; then
                echo "⚠️ [opencode] jq not installed; using default config"
                JQ_FILTER='.'
            else
                echo "...[opencode] Applying baseURL override"
                JQ_FILTER=".provider.ollama.options.baseURL = \"${OLLAMA_BASE_URL}\""
            fi
        else
            echo "...[opencode] OLLAMA_BASE_URL not set; using config default"
            JQ_FILTER='.'
        fi

        echo "...[opencode] Hydrating config"
        jq \
            "$JQ_FILTER" \
            "$SOURCE_CONFIG" > "$TARGET_CONFIG.tmp"

        if [[ $? -eq 0 ]]; then
            mv "$TARGET_CONFIG.tmp" "$TARGET_CONFIG"
            echo "✔ [opencode] Config written"
            chmod 644 "$TARGET_CONFIG" 2>/dev/null || true
        else
            echo "⚠️ [opencode] jq failed; leaving existing config untouched"
            rm -f "$TARGET_CONFIG.tmp"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Finish
# -----------------------------------------------------------------------------

echo ""
echo "🎉 Dotfiles installation complete"