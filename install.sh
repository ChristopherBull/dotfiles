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
    elif [[ -f "$TARGET_CONFIG" ]]; then
        echo "✅ [opencode] Config already exists; skipping (delete to re-hydrate)"
    else
        mkdir -p "$TARGET_DIR"

        OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-}"

        if [[ -n "$OLLAMA_BASE_URL" ]]; then
            echo "...[opencode] OLLAMA_BASE_URL=$OLLAMA_BASE_URL"

            if ! command -v jq >/dev/null 2>&1; then
                echo "⚠️ [opencode] jq not installed; cannot apply baseURL override"
                echo "...[opencode] Copying default config without URL override"
                cp "$SOURCE_CONFIG" "$TARGET_CONFIG"
            else
                echo "...[opencode] Applying baseURL override with jq"
                jq ".provider.ollama.options.baseURL = \"${OLLAMA_BASE_URL}\"" \
                    "$SOURCE_CONFIG" > "$TARGET_CONFIG.tmp" \
                    && mv "$TARGET_CONFIG.tmp" "$TARGET_CONFIG" \
                    || { echo "⚠️ [opencode] jq failed; copying default config"; cp "$SOURCE_CONFIG" "$TARGET_CONFIG"; rm -f "$TARGET_CONFIG.tmp"; }
            fi
        else
            echo "...[opencode] OLLAMA_BASE_URL not set; copying default config"
            cp "$SOURCE_CONFIG" "$TARGET_CONFIG"
        fi

        chmod 644 "$TARGET_CONFIG" 2>/dev/null || true
        echo "✔ [opencode] Config written"
    fi
fi

# -----------------------------------------------------------------------------
# VS Code user settings
# -----------------------------------------------------------------------------

echo ""
echo "🖥️ VS Code configuration"

# Identify if VS Code is installed by checking for the `code` CLI
if ! command -v code >/dev/null 2>&1; then
    echo "⏭️ [vscode] Not installed; skipping"
else
    echo "...[vscode] Detected: $(code --version 2>/dev/null | head -1)"

    SOURCE_VSCODE_SETTINGS="$DOTFILES_DIR/.config/.vscode/user.settings.json"

    if [[ ! -f "$SOURCE_VSCODE_SETTINGS" ]]; then
        echo "⚠️ [vscode] Missing source settings: $SOURCE_VSCODE_SETTINGS"
        echo "...[vscode] Skipping configuration"
    else
        # Resolve the OS-specific path to the VS Code user settings file
        case "$(uname -s)" in
            Darwin)
                VSCODE_USER_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
                ;;
            Linux)
                VSCODE_USER_SETTINGS="$HOME/.config/Code/User/settings.json"
                ;;
            *)
                echo "⚠️ [vscode] Unsupported OS: $(uname -s); cannot determine settings path"
                VSCODE_USER_SETTINGS=""
                ;;
        esac

        if [[ -z "$VSCODE_USER_SETTINGS" ]]; then
            echo "...[vscode] Skipping configuration"
        elif [[ ! -f "$VSCODE_USER_SETTINGS" ]]; then
            # No existing settings file — copy dotfiles settings directly
            echo "...[vscode] No existing settings found; copying dotfiles settings"
            mkdir -p "$(dirname "$VSCODE_USER_SETTINGS")"
            cp "$SOURCE_VSCODE_SETTINGS" "$VSCODE_USER_SETTINGS"
            echo "✅ [vscode] Settings applied"
        else
            echo "...[vscode] Existing settings found at: $VSCODE_USER_SETTINGS"
            echo "...[vscode] Merging dotfiles settings into user settings"

            # jq is required to deep-merge the two JSON settings files
            if ! command -v jq >/dev/null 2>&1; then
                echo "⚠️ [vscode] jq not installed; cannot merge settings"
                echo "...[vscode] Skipping (install jq and re-run to apply)"
            else
                # Deep merge strategy:
                #   - Objects are merged recursively; dotfiles values take precedence over existing
                #   - Arrays are unioned (combined + deduplicated) so existing user values are preserved
                MERGED=$(jq -s '
                    def deepmerge(a; b):
                        if (a | type) == "object" and (b | type) == "object" then
                            reduce (b | keys_unsorted[]) as $key (
                                a;
                                . + { ($key): deepmerge(a[$key]; b[$key]) }
                            )
                        elif (a | type) == "array" and (b | type) == "array" then
                            (a + b | unique)
                        elif b == null then a
                        else b
                        end;
                    deepmerge(.[0]; .[1])
                ' "$VSCODE_USER_SETTINGS" "$SOURCE_VSCODE_SETTINGS") || {
                    echo "⚠️ [vscode] jq merge failed; skipping"
                    MERGED=""
                }

                if [[ -n "$MERGED" ]]; then
                    # Write to a temp file first, then atomically replace to avoid partial writes
                    echo "$MERGED" > "$VSCODE_USER_SETTINGS.tmp" \
                        && mv "$VSCODE_USER_SETTINGS.tmp" "$VSCODE_USER_SETTINGS" \
                        || { echo "⚠️ [vscode] Failed to write merged settings"; rm -f "$VSCODE_USER_SETTINGS.tmp"; }
                    echo "✅ [vscode] Settings merged"
                fi
            fi
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Global Git attributes
# -----------------------------------------------------------------------------

echo ""
echo "🔗 Global Git attributes"

SOURCE_GIT_ATTRS="$DOTFILES_DIR/.config/git/attributes"
TARGET_GIT_ATTRS="$HOME/.config/git/attributes"

if [[ ! -f "$SOURCE_GIT_ATTRS" ]]; then
    echo "⚠️ [git] Missing source: $SOURCE_GIT_ATTRS; skipping"
else
    mkdir -p "$(dirname "$TARGET_GIT_ATTRS")"
    # Symlink so future updates propagate automatically. ~/.config/git/attributes
    # is Git's default global attributes path (no `git config` needed).
    ln -sf "$SOURCE_GIT_ATTRS" "$TARGET_GIT_ATTRS"
    echo "✅ [git] Linked $TARGET_GIT_ATTRS"
fi

# -----------------------------------------------------------------------------
# Global Claude Code settings
# -----------------------------------------------------------------------------

echo ""
echo "🤖 Global Claude Code settings"

# --- Personal CLAUDE.md (user-scoped memory) ---
SOURCE_CLAUDE_MD="$DOTFILES_DIR/.config/claude/CLAUDE.md"
TARGET_CLAUDE_MD="$HOME/.claude/CLAUDE.md"

if [[ ! -f "$SOURCE_CLAUDE_MD" ]]; then
    echo "⚠️ [claude] Missing source: $SOURCE_CLAUDE_MD; skipping CLAUDE.md"
else
    mkdir -p "$(dirname "$TARGET_CLAUDE_MD")"
    # Symlink — dotfiles fully owns this personal-prefs file.
    ln -sf "$SOURCE_CLAUDE_MD" "$TARGET_CLAUDE_MD"
    echo "✅ [claude] Linked $TARGET_CLAUDE_MD"
fi

# --- Global settings.json (allowlist; merged to preserve existing) ---
SOURCE_CLAUDE_SETTINGS="$DOTFILES_DIR/.config/claude/settings.json"
TARGET_CLAUDE_SETTINGS="$HOME/.claude/settings.json"

if [[ ! -f "$SOURCE_CLAUDE_SETTINGS" ]]; then
    echo "⚠️ [claude] Missing source: $SOURCE_CLAUDE_SETTINGS; skipping"
elif [[ ! -f "$TARGET_CLAUDE_SETTINGS" ]]; then
    echo "...[claude] No existing settings; copying dotfiles settings"
    mkdir -p "$(dirname "$TARGET_CLAUDE_SETTINGS")"
    cp "$SOURCE_CLAUDE_SETTINGS" "$TARGET_CLAUDE_SETTINGS"
    echo "✅ [claude] Settings applied"
elif ! command -v jq >/dev/null 2>&1; then
    echo "⚠️ [claude] jq not installed; cannot merge into existing settings"
    echo "...[claude] Skipping (install jq and re-run to apply)"
else
    echo "...[claude] Existing settings found; merging allowlist"
    # Union the permissions.allow arrays so dotfiles entries are added without
    # discarding any the user already has. Other keys: dotfiles take precedence.
    MERGED=$(jq -s '
        def deepmerge(a; b):
            if (a | type) == "object" and (b | type) == "object" then
                reduce (b | keys_unsorted[]) as $key (
                    a;
                    . + { ($key): deepmerge(a[$key]; b[$key]) }
                )
            elif (a | type) == "array" and (b | type) == "array" then
                (a + b | unique)
            elif b == null then a
            else b
            end;
        deepmerge(.[0]; .[1])
    ' "$TARGET_CLAUDE_SETTINGS" "$SOURCE_CLAUDE_SETTINGS") || {
        echo "⚠️ [claude] jq merge failed; skipping"
        MERGED=""
    }

    if [[ -n "$MERGED" ]]; then
        echo "$MERGED" > "$TARGET_CLAUDE_SETTINGS.tmp" \
            && mv "$TARGET_CLAUDE_SETTINGS.tmp" "$TARGET_CLAUDE_SETTINGS" \
            || { echo "⚠️ [claude] Failed to write merged settings"; rm -f "$TARGET_CLAUDE_SETTINGS.tmp"; }
        echo "✅ [claude] Settings merged"
    fi
fi

# -----------------------------------------------------------------------------
# Finish
# -----------------------------------------------------------------------------

echo ""
echo "🎉 Dotfiles installation complete"