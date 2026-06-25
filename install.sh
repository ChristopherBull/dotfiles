#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------

echo ""
echo "🚀 Starting dotfiles installation"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Writes $content to $target via a temp file, then prints $ok_msg or $fail_msg.
write_atomic() {
    local content="$1" target="$2" ok_msg="$3" fail_msg="$4"
    if echo "$content" > "$target.tmp" && mv "$target.tmp" "$target"; then
        echo "$ok_msg"
    else
        echo "$fail_msg"
        rm -f "$target.tmp"
    fi
}

# Merges objects recursively (dotfiles wins on conflict) and unions arrays.
# shellcheck disable=SC2016
JQ_DEEPMERGE='
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
'

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

    # shellcheck disable=SC2016
    # Single quotes are intentional: write the literal `eval "$(starship init …)"`
    # line into the rc file so it runs at every shell startup, not at install time.
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

    # Starship config
    SOURCE_STARSHIP_CONFIG="$DOTFILES_DIR/.config/starship/starship.toml"
    TARGET_STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"

    if [[ ! -f "$SOURCE_STARSHIP_CONFIG" ]]; then
        echo "⚠️ [starship] Missing source config: $SOURCE_STARSHIP_CONFIG; skipping"
    else
        mkdir -p "$(dirname "$TARGET_STARSHIP_CONFIG")"
        ln -sf "$SOURCE_STARSHIP_CONFIG" "$TARGET_STARSHIP_CONFIG"
        echo "✅ [starship] Config linked to $TARGET_STARSHIP_CONFIG"
    fi
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

    SOURCE_CONFIG="$DOTFILES_DIR/.config/opencode/opencode.json"
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
                if jq ".provider.ollama.options.baseURL = \"${OLLAMA_BASE_URL}\"" \
                    "$SOURCE_CONFIG" > "$TARGET_CONFIG.tmp" \
                    && mv "$TARGET_CONFIG.tmp" "$TARGET_CONFIG"; then
                    echo "...[opencode] baseURL override applied"
                else
                    echo "⚠️ [opencode] jq failed; copying default config"
                    cp "$SOURCE_CONFIG" "$TARGET_CONFIG"
                    rm -f "$TARGET_CONFIG.tmp"
                fi
            fi
        else
            echo "...[opencode] OLLAMA_BASE_URL not set; copying default config"
            cp "$SOURCE_CONFIG" "$TARGET_CONFIG"
        fi

        chmod 644 "$TARGET_CONFIG" 2>/dev/null || true
        echo "✅ [opencode] Config written"
    fi
fi

# -----------------------------------------------------------------------------
# ripgrep (required by VS Code extension: Gruntfuggly.todo-tree)
# -----------------------------------------------------------------------------

echo ""
echo "🔍 ripgrep"

install_ripgrep() {
    echo "...[rg] Attempting installation"

    if command -v brew >/dev/null 2>&1; then
        echo "...[rg] Using Homebrew"
        brew install ripgrep

    elif command -v apt-get >/dev/null 2>&1; then
        echo "...[rg] Using apt-get"
        sudo apt-get update
        sudo apt-get install -y ripgrep

    elif command -v dnf >/dev/null 2>&1; then
        echo "...[rg] Using dnf"
        sudo dnf install -y ripgrep

    elif command -v yum >/dev/null 2>&1; then
        echo "...[rg] Using yum"
        sudo yum install -y ripgrep

    elif command -v pacman >/dev/null 2>&1; then
        echo "...[rg] Using pacman"
        sudo pacman -S --noconfirm ripgrep

    elif command -v winget >/dev/null 2>&1; then
        echo "...[rg] Using winget"
        winget install BurntSushi.ripgrep.MSVC

    else
        echo "❌ [rg] No supported package manager found"
        return 1
    fi

    echo "✅ [rg] Installed"
}

if command -v rg >/dev/null 2>&1; then
    echo "✅ [rg] Already installed: $(rg --version | head -1)"
else
    echo "...[rg] Not found"
    install_ripgrep
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
                MERGED=$(jq -s "$JQ_DEEPMERGE deepmerge(.[0]; .[1])" \
                    "$VSCODE_USER_SETTINGS" "$SOURCE_VSCODE_SETTINGS") || {
                    echo "⚠️ [vscode] jq merge failed; skipping"
                    MERGED=""
                }

                if [[ -n "$MERGED" ]]; then
                    write_atomic "$MERGED" "$VSCODE_USER_SETTINGS" \
                        "✅ [vscode] Settings merged" \
                        "⚠️ [vscode] Failed to write merged settings"
                fi
            fi
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Ghostty terminal config
# -----------------------------------------------------------------------------

echo ""
echo "👻 Ghostty configuration"

SOURCE_GHOSTTY_CONFIG="$DOTFILES_DIR/.config/ghostty/config.ghostty"

# shellcheck disable=SC2016
add_line_if_missing 'export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"' ~/.zshrc
echo "✅ [ghostty] XDG_CONFIG_HOME set in ~/.zshrc"

if [[ ! -f "$SOURCE_GHOSTTY_CONFIG" ]]; then
    echo "⚠️ [ghostty] Missing source config: $SOURCE_GHOSTTY_CONFIG; skipping"
else
    TARGET_GHOSTTY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config.ghostty"

    if [[ -f "$TARGET_GHOSTTY_CONFIG" ]] && [[ -s "$TARGET_GHOSTTY_CONFIG" ]]; then
        echo "✅ [ghostty] Config already exists and is non-empty; skipping"
    else
        mkdir -p "$(dirname "$TARGET_GHOSTTY_CONFIG")"
        ln -sf "$SOURCE_GHOSTTY_CONFIG" "$TARGET_GHOSTTY_CONFIG"
        echo "✅ [ghostty] Config linked to $TARGET_GHOSTTY_CONFIG"
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
    MERGED=$(jq -s "$JQ_DEEPMERGE deepmerge(.[0]; .[1])" \
        "$TARGET_CLAUDE_SETTINGS" "$SOURCE_CLAUDE_SETTINGS") || {
        echo "⚠️ [claude] jq merge failed; skipping"
        MERGED=""
    }

    if [[ -n "$MERGED" ]]; then
        write_atomic "$MERGED" "$TARGET_CLAUDE_SETTINGS" \
            "✅ [claude] Settings merged" \
            "⚠️ [claude] Failed to write merged settings"
    fi
fi

# -----------------------------------------------------------------------------
# Language LSP plugins
# -----------------------------------------------------------------------------

echo ""
echo "🔌 Language LSP plugins"

# The install script runs from the dotfiles dir, not the project repo.
find_project_root() {
    local root
    if [[ -n "${CODESPACE_VSCODE_FOLDER:-}" ]]; then
        root="$CODESPACE_VSCODE_FOLDER"
    elif [[ -d /workspaces ]]; then
        local dir
        for dir in /workspaces/*/; do
            [[ "${dir%/}" == "$DOTFILES_DIR" ]] && continue
            if [[ -d "$dir/.git" ]]; then
                root="${dir%/}"
                break
            fi
        done
    fi
    root="${root:-$(pwd)}"
    echo "...[lsp] Project root: $root" >&2
    echo "$root"
}

detect_languages() {
    local root
    root="$(find_project_root)"

    if [[ -f "$root/.mise.toml" ]]; then
        echo "...[lsp] Deriving languages from .mise.toml" >&2
        grep -qE '^\s*python\s*=' "$root/.mise.toml" && echo python
        grep -qE '^\s*node\s*=' "$root/.mise.toml" && echo node
        grep -qE '^\s*rust\s*=' "$root/.mise.toml" && echo rust
        grep -qE '^\s*go\s*=' "$root/.mise.toml" && echo go
        return
    fi

    if [[ -f "$root/.tool-versions" ]]; then
        echo "...[lsp] Deriving languages from .tool-versions" >&2
        grep -qE '^python' "$root/.tool-versions" && echo python
        grep -qE '^node(js)?' "$root/.tool-versions" && echo node
        grep -qE '^rust' "$root/.tool-versions" && echo rust
        grep -qE '^(go|golang)' "$root/.tool-versions" && echo go
        return
    fi

    echo "...[lsp] No toolchain manifest; using language-file fallbacks" >&2
    if [[ -f "$root/pyproject.toml" ]] || [[ -f "$root/requirements.txt" ]] || [[ -f "$root/setup.py" ]]; then
        echo python
    fi
    [[ -f "$root/package.json" ]] && echo node
    [[ -f "$root/Cargo.toml" ]] && echo rust
    [[ -f "$root/go.mod" ]] && echo go
}

# Plugin registry: maps language → plugin name for Claude Code (claude plugins install <name>).
# Extend here without touching detection logic.
declare -A CLAUDE_PLUGINS=(
    [python]="pyright-lsp"
    [node]="typescript-lsp"
    [rust]="rust-analyzer"
    [go]="gopls"
)

# LSP server configs for OpenCode, merged into opencode.json under the "lsp" key.
# OpenCode resolves these via the declared command — the server binary must be on PATH.
declare -A OPENCODE_LSP_CONFIGS=(
    [python]='{"command":["pyright-langserver","--stdio"],"extensions":[".py"]}'
    [node]='{"command":["typescript-language-server","--stdio"],"extensions":[".js",".ts",".jsx",".tsx"]}'
    [rust]='{"command":["rust-analyzer"],"extensions":[".rs"]}'
    [go]='{"command":["gopls"],"extensions":[".go"]}'
)

install_claude_plugins() {
    local lang="$1"
    local plugin

    [[ -n "${CLAUDE_PLUGINS[$lang]+_}" ]] || return 0
    command -v claude >/dev/null 2>&1 || return 0

    plugin="${CLAUDE_PLUGINS[$lang]}"
    echo "...[lsp] Installing Claude plugin for $lang: $plugin"
    # claude prints its own success line; only surface failures ourselves
    claude plugins install "$plugin" || echo "⚠️ [lsp] claude: failed to install $plugin"
}

configure_opencode_lsp() {
    local target="$HOME/.config/opencode/opencode.json"
    local lang config_json patch merged

    command -v opencode >/dev/null 2>&1 || return 0

    if [[ ! -f "$target" ]]; then
        echo "...[lsp] opencode: config not found; skipping LSP merge"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "⚠️ [lsp] opencode: jq not installed; cannot merge LSP config"
        return 0
    fi

    patch="{}"
    for lang in "$@"; do
        [[ -n "${OPENCODE_LSP_CONFIGS[$lang]+_}" ]] || continue
        config_json="${OPENCODE_LSP_CONFIGS[$lang]}"
        patch=$(printf '%s' "$patch" | jq --arg key "$lang" --argjson val "$config_json" '. + {($key): $val}')
    done

    [[ "$patch" == "{}" ]] && return 0

    echo "...[lsp] opencode: merging LSP entries: $(printf '%s' "$patch" | jq -r '[keys[]] | join(", ")')"

    merged=$(jq --argjson lsp "$patch" '.lsp = ((.lsp // {}) + $lsp)' "$target") || {
        echo "⚠️ [lsp] opencode: jq merge failed"
        return 1
    }

    write_atomic "$merged" "$target" \
        "✅ [lsp] opencode: LSP config merged" \
        "⚠️ [lsp] opencode: failed to write merged config"
}

mapfile -t DETECTED_LANGS < <(detect_languages)

if [[ ${#DETECTED_LANGS[@]} -eq 0 ]]; then
    echo "...[lsp] No languages detected; skipping"
else
    echo "...[lsp] Detected: ${DETECTED_LANGS[*]}"

    for lang in "${DETECTED_LANGS[@]}"; do
        install_claude_plugins "$lang"
    done

    configure_opencode_lsp "${DETECTED_LANGS[@]}"
fi

# -----------------------------------------------------------------------------
# Finish
# -----------------------------------------------------------------------------

echo ""
echo "🎉 Dotfiles installation complete"