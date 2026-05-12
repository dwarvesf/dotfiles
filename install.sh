#!/bin/bash
set -e

# Bootstrap script for dotfiles.
# Idempotent: safe to run multiple times on an already-configured machine.
# Use --force to teardown and reinit from scratch.
# Use --check to dry-run without applying changes.
# Use --config-only to deploy configs without running scripts (brew, mas, defaults).
#
# Exit codes:
#   0 = success
#   1 = Homebrew install failed
#   2 = chezmoi init/apply failed

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
FORCE=0
CHECK_ONLY=0
CONFIG_ONLY=0

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --check) CHECK_ONLY=1 ;;
        --config-only) CONFIG_ONLY=1 ;;
    esac
done

echo "==> Dotfiles: $DOTFILES"

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew"
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        echo "==> ERROR: Homebrew install failed"
        exit 1
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "==> Homebrew: already installed"
fi

# --- chezmoi + gum ---
if ! command -v chezmoi &>/dev/null; then
    echo "==> Installing chezmoi"
    brew install chezmoi
else
    echo "==> chezmoi: already installed"
fi

if ! command -v gum &>/dev/null; then
    echo "==> Installing gum"
    brew install gum
else
    echo "==> gum: already installed"
fi

# --- Helper functions ---
link_is_correct() {
    [ -L "$CHEZMOI_SOURCE" ] && [ "$(readlink "$CHEZMOI_SOURCE")" = "$DOTFILES/home" ]
}

chezmoi_initialized() {
    [ -f "$CHEZMOI_CONFIG" ]
}

ensure_link() {
    if ! link_is_correct; then
        if [ -e "$CHEZMOI_SOURCE" ] && ! [ -L "$CHEZMOI_SOURCE" ]; then
            echo "==> WARNING: $CHEZMOI_SOURCE exists and is not a symlink. Backing up."
            mv "$CHEZMOI_SOURCE" "$CHEZMOI_SOURCE.bak.$(date +%s)"
        elif [ -L "$CHEZMOI_SOURCE" ]; then
            echo "==> Symlink points to wrong location. Relinking."
            rm -f "$CHEZMOI_SOURCE"
        fi
        echo "==> Linking chezmoi source to $DOTFILES/home"
        mkdir -p "$HOME/.local/share"
        ln -sf "$DOTFILES/home" "$CHEZMOI_SOURCE"
    fi
}

apply_flags() {
    if [ "$CONFIG_ONLY" -eq 1 ]; then
        echo "--exclude=scripts"
    fi
}

# --- Gum wizard ---

# Colors: 75=steel blue, 117=light blue, 251=light gray, 10=green
WIZ_ACCENT=75
WIZ_LIGHT=117
WIZ_DIM=251

# Styled read prompt (no gum input, avoids duplicate line issue)
# Sets REPLY variable directly (can't use $() because read needs TTY)
# Usage: styled_read "Label" "default_value"; myvar="$REPLY"
styled_read() {
    local label=$1 default=$2
    if [ -n "$default" ]; then
        printf '\033[38;5;%sm  %s \033[38;5;%sm[%s] \033[0m' "$WIZ_DIM" "$label" "$WIZ_DIM" "$default"
    else
        printf '\033[38;5;%sm  %s \033[0m' "$WIZ_DIM" "$label"
    fi
    if ! read -r REPLY; then
        echo ""
        echo "==> Cancelled."
        exit 0
    fi
    if [ -z "$REPLY" ]; then
        REPLY="$default"
    fi
}

# Draw the wizard header + progress bar + completed answers
# Builds output in a buffer first, then prints all at once to minimize flicker
draw_wizard() {
    local step=$1 total=4
    local buf=""

    # Header
    buf+="$(gum style --border rounded --padding "1 2" --border-foreground "$WIZ_ACCENT" \
        "  dotfiles setup  ")"
    buf+=$'\n\n'

    # Progress bar
    local filled=$((step * 20 / total))
    local empty=$((20 - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    buf+="$(gum style --foreground "$WIZ_ACCENT" "  $bar  Step $step/$total")"
    buf+=$'\n\n'

    # Show completed answers
    [ -n "${wiz_name+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ Name:      '"$wiz_name"$'\033[0m\n'
    [ -n "${wiz_email+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ Email:     '"$wiz_email"$'\033[0m\n'
    [ -n "${wiz_editor+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ Editor:    '"$wiz_editor"$'\033[0m\n'
    [ -n "${wiz_headless+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ Headless:  '"$wiz_headless"$'\033[0m\n'
    [ -n "${wiz_1pass+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ 1Password: '"$wiz_1pass"$'\033[0m\n'
    [ -n "${wiz_account+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ Account:   '"$wiz_account"$'\033[0m\n'
    [ -n "${wiz_vault+x}" ] && buf+=$'\033[38;5;'"${WIZ_DIM}"'m  ✓ Vault:     '"$wiz_vault"$'\033[0m\n'
    buf+=$'\n'

    # Clear screen and print buffer in one shot
    printf '\033[H\033[J%s' "$buf"
}

run_gum_wizard() {
    # Gum reads env vars as config flags. Shell theming vars like UNDERLINE, BOLD,
    # ITALIC (ANSI escape codes) conflict with gum's boolean flags. Unset them.
    unset UNDERLINE BOLD ITALIC

    # Trap Ctrl+C to exit cleanly from the wizard
    trap 'echo ""; echo "==> Cancelled."; exit 0' INT

    local name email editor headless use_1password op_account op_vault

    # --- Step 1: Identity (name + email, no redraw between them) ---
    draw_wizard 1
    gum style --foreground "$WIZ_LIGHT" --bold "  Identity"
    echo ""
    styled_read "Name:" "$(git config user.name 2>/dev/null || true)"
    name="$REPLY"; wiz_name="$name"
    styled_read "Email:" "$(git config user.email 2>/dev/null || true)"
    email="$REPLY"; wiz_email="$email"

    # --- Step 2: Editor ---
    draw_wizard 2
    gum style --foreground "$WIZ_LIGHT" --bold "  Editor"
    echo ""
    gum style --foreground "$WIZ_DIM" "  Pick your default editor:"
    editor=$(gum choose \
        --cursor.foreground "$WIZ_ACCENT" --selected.foreground 10 \
        "code --wait" "zed --wait" "nvim" "vim")
    wiz_editor="$editor"

    # --- Step 3: Environment ---
    draw_wizard 3
    gum style --foreground "$WIZ_LIGHT" --bold "  Environment"
    echo ""
    gum style --foreground "$WIZ_DIM" "  Server/CI mode: only install base CLI tools."
    gum style --foreground "$WIZ_DIM" "  Say No for a full setup with dev tools and GUI apps."
    echo ""
    if gum confirm --default=no "  Headless/server environment?"; then
        headless=true
    else
        headless=false
    fi
    wiz_headless="$headless"

    # --- Step 4: Secrets ---
    draw_wizard 4
    gum style --foreground "$WIZ_LIGHT" --bold "  Secrets"
    echo ""
    op_account=""
    op_vault=""
    gum style --foreground "$WIZ_DIM" "  Inject API keys and tokens from 1Password at apply time."
    gum style --foreground "$WIZ_DIM" "  Say No if you don't use 1Password (you can enable later)."
    echo ""
    if gum confirm "  Use 1Password for secrets?"; then
        use_1password=true
        wiz_1pass="enabled"
        styled_read "Account:" "my.1password.com"
        op_account="$REPLY"; wiz_account="$op_account"
        styled_read "Vault:" "Private"
        op_vault="$REPLY"; wiz_vault="$op_vault"
    else
        use_1password=false
        wiz_1pass="disabled"
    fi

    # --- Summary ---
    draw_wizard 4
    gum style --foreground "$WIZ_LIGHT" --bold "  All set!"
    echo ""
    if ! gum confirm --affirmative "Apply" --negative "Cancel" "  Save this config?"; then
        echo "==> Cancelled."
        exit 0
    fi

    # Restore default signal handling
    trap - INT

    # Write chezmoi config
    mkdir -p "$(dirname "$CHEZMOI_CONFIG")"
    cat > "$CHEZMOI_CONFIG" <<EOF
[data]
  name = "$name"
  email = "$email"
  editor = "$editor"
  headless = $headless
  use_1password = $use_1password
  op_account = "$op_account"
  op_vault = "$op_vault"
EOF

    echo ""
    gum style --foreground 10 "  Config saved."
}

# --- Plain fallback wizard (no gum / no TTY) ---
run_plain_wizard() {
    echo ""
    echo "==> dotfiles setup"
    echo ""

    local name email editor headless use_1password op_account op_vault

    read -rp "Full name (for git): " name
    read -rp "Email address: " email
    echo "Default editor:"
    echo "  1) code --wait"
    echo "  2) zed --wait"
    echo "  3) nvim"
    echo "  4) vim"
    read -rp "Choice [1-4]: " editor_choice
    case "$editor_choice" in
        1) editor="code --wait" ;;
        2) editor="zed --wait" ;;
        3) editor="nvim" ;;
        *) editor="vim" ;;
    esac

    read -rp "Headless/server environment? (y/N): " headless_input
    if [ "$headless_input" = "y" ] || [ "$headless_input" = "Y" ]; then
        headless=true
    else
        headless=false
    fi

    op_account=""
    op_vault=""
    read -rp "Use 1Password for secrets? (y/N): " op_input
    if [ "$op_input" = "y" ] || [ "$op_input" = "Y" ]; then
        use_1password=true
        read -rp "1Password account [my.1password.com]: " op_account
        op_account="${op_account:-my.1password.com}"
        read -rp "1Password vault [Private]: " op_vault
        op_vault="${op_vault:-Private}"
    else
        use_1password=false
    fi

    mkdir -p "$(dirname "$CHEZMOI_CONFIG")"
    cat > "$CHEZMOI_CONFIG" <<EOF
[data]
  name = "$name"
  email = "$email"
  editor = "$editor"
  headless = $headless
  use_1password = $use_1password
  op_account = "$op_account"
  op_vault = "$op_vault"
EOF

    echo ""
    echo "==> Config saved to $CHEZMOI_CONFIG"
}

# --- Run wizard (gum or fallback) ---
run_wizard() {
    if command -v gum &>/dev/null && [ -t 0 ]; then
        run_gum_wizard
        # Let chezmoi init validate template + fill any gaps the wizard missed
        chezmoi init
    elif [ -t 0 ]; then
        run_plain_wizard
        chezmoi init
    else
        # Non-interactive: chezmoi init reads from existing config or fails
        echo "==> Non-interactive mode. Running chezmoi init."
        chezmoi init
    fi
}

# --- Apply ---
run_apply() {
    if [ "$CHECK_ONLY" -eq 1 ]; then
        echo "==> Dry run (--check mode)"
        if ! chezmoi apply --dry-run --verbose; then
            echo "==> ERROR: chezmoi dry-run failed"
            exit 2
        fi
        echo "==> Dry run passed. No changes applied."
        return 0
    fi

    if [ "$CONFIG_ONLY" -eq 1 ]; then
        echo "==> Config-only mode: deploying files, skipping scripts"
    fi

    # Run apply, show spinner if gum available. Use temp file to capture errors
    # since gum spin suppresses output.
    local apply_log
    apply_log=$(mktemp)
    local apply_cmd="chezmoi apply"
    if [ "$CONFIG_ONLY" -eq 1 ]; then
        apply_cmd="chezmoi apply --exclude=scripts"
    fi

    if command -v gum &>/dev/null && [ -t 0 ]; then
        if ! gum spin --spinner dot --title "Applying configs..." -- \
            bash -c "$apply_cmd 2>\"$apply_log\""; then
            echo "==> ERROR: chezmoi apply failed"
            cat "$apply_log" 2>/dev/null
            rm -f "$apply_log"
            exit 2
        fi
    else
        if ! bash -c "$apply_cmd 2>\"$apply_log\""; then
            echo "==> ERROR: chezmoi apply failed"
            cat "$apply_log" 2>/dev/null
            rm -f "$apply_log"
            exit 2
        fi
    fi
    rm -f "$apply_log"
}

verify_deployment() {
    echo "==> Verifying deployment..."
    local warnings=0
    for f in ~/.config/fish/config.fish ~/.gitconfig ~/.ssh/config; do
        if [ ! -f "$f" ]; then
            echo "==> WARNING: Expected $f but it doesn't exist"
            warnings=$((warnings + 1))
        fi
    done
    if [ "$warnings" -eq 0 ]; then
        if command -v gum &>/dev/null; then
            gum style --foreground 10 "  All key files verified."
        else
            echo "==> All key files verified."
        fi
    fi
}

# --- Determine what to do ---
if [ "$FORCE" -eq 1 ]; then
    echo "==> --force: tearing down existing state"
    rm -rf "$CHEZMOI_SOURCE"
    rm -f "$CHEZMOI_CONFIG"
    ensure_link
    run_wizard
    run_apply

elif command -v chezmoi &>/dev/null && link_is_correct && chezmoi_initialized; then
    echo "==> Already initialized. Running chezmoi apply..."
    run_apply

elif command -v chezmoi &>/dev/null; then
    ensure_link
    if [ "$CHECK_ONLY" -eq 1 ]; then
        echo "==> Dry run (--check mode, not yet initialized)"
        echo "==> Run without --check first to set up config."
        exit 0
    fi
    run_wizard
    run_apply
fi

# --- Set fish as default shell (always runs, even with --config-only) ---
if [ "$CHECK_ONLY" -eq 0 ]; then
    FISH_PATH="/opt/homebrew/bin/fish"
    if command -v fish &>/dev/null; then
        if ! grep -q "$FISH_PATH" /etc/shells 2>/dev/null; then
            echo "==> Adding fish to /etc/shells (requires sudo)"
            echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
        fi
        if [ "$SHELL" != "$FISH_PATH" ]; then
            echo "==> Setting fish as default shell"
            chsh -s "$FISH_PATH" || echo "==> Run manually: chsh -s $FISH_PATH"
        fi
    fi
fi

# --- Post-apply verification ---
if [ "$CHECK_ONLY" -eq 0 ]; then
    verify_deployment
fi

# --- Brew package check (smart: skips packages available outside brew) ---
check_formula_installed() {
    # Check if a formula's command exists in PATH (even if not from brew)
    local pkg=$1
    # Some formulae have different command names
    case "$pkg" in
        git-delta) command -v delta &>/dev/null ;;
        git-filter-repo) command -v git-filter-repo &>/dev/null ;;
        git-sizer) command -v git-sizer &>/dev/null ;;
        kubernetes-cli) command -v kubectl &>/dev/null ;;
        python@*) command -v python3 &>/dev/null ;;
        choose-rust) command -v choose &>/dev/null ;;
        1password-cli) command -v op &>/dev/null ;;
        *) command -v "$pkg" &>/dev/null ;;
    esac
}

check_cask_installed() {
    # Check if a cask's .app exists in /Applications (even if not from brew)
    local cask=$1
    case "$cask" in
        1password) [ -d "/Applications/1Password.app" ] ;;
        visual-studio-code) [ -d "/Applications/Visual Studio Code.app" ] ;;
        google-chrome) [ -d "/Applications/Google Chrome.app" ] ;;
        microsoft-edge) [ -d "/Applications/Microsoft Edge.app" ] ;;
        tor-browser) [ -d "/Applications/Tor Browser.app" ] ;;
        zen-browser) [ -d "/Applications/Zen.app" ] || [ -d "/Applications/Zen Browser.app" ] ;;
        monitor-control) [ -d "/Applications/MonitorControl.app" ] ;;
        font-*) true ;;  # Skip font checks, hard to verify
        *)
            # Convert kebab-case to title case for app lookup
            local app_name
            app_name=$(echo "$cask" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
            [ -d "/Applications/$app_name.app" ]
            ;;
    esac
}

if [ "$CHECK_ONLY" -eq 0 ] && [ -f "$HOME/.Brewfile" ] && command -v brew &>/dev/null; then
    missing_raw=$(brew bundle check --file="$HOME/.Brewfile" --no-upgrade --verbose 2>&1 | grep "needs to be installed" || true)
    if [ -n "$missing_raw" ]; then
        # Filter out packages that are actually installed (just not via brew)
        truly_missing_formulae=""
        truly_missing_casks=""

        while IFS= read -r line; do
            pkg=$(echo "$line" | sed 's/→ Formula //' | sed 's/ needs to be .*//')
            if ! check_formula_installed "$pkg"; then
                truly_missing_formulae+="$pkg"$'\n'
            fi
        done <<< "$(echo "$missing_raw" | grep "^→ Formula" || true)"

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            cask=$(echo "$line" | sed 's/→ Cask //' | sed 's/ needs to be .*//')
            if ! check_cask_installed "$cask"; then
                truly_missing_casks+="$cask"$'\n'
            fi
        done <<< "$(echo "$missing_raw" | grep "^→ Cask" || true)"

        # Trim trailing newlines
        truly_missing_formulae=$(echo "$truly_missing_formulae" | sed '/^$/d')
        truly_missing_casks=$(echo "$truly_missing_casks" | sed '/^$/d')

        formulae_count=0
        casks_count=0
        [ -n "$truly_missing_formulae" ] && formulae_count=$(echo "$truly_missing_formulae" | wc -l | tr -d ' ')
        [ -n "$truly_missing_casks" ] && casks_count=$(echo "$truly_missing_casks" | wc -l | tr -d ' ')
        total_missing=$((formulae_count + casks_count))

        if [ "$total_missing" -gt 0 ]; then
            echo ""
            if command -v gum &>/dev/null; then
                gum style --border rounded --padding "1 2" --border-foreground 214 \
                    "  $total_missing packages not yet installed"
                echo ""
                if [ -n "$truly_missing_formulae" ]; then
                    gum style --foreground "$WIZ_LIGHT" "  CLI tools ($formulae_count):"
                    echo "$truly_missing_formulae" | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//' | fmt -w 56 | while IFS= read -r fline; do
                        printf '\033[38;5;%sm    %s\033[0m\n' "$WIZ_DIM" "$fline"
                    done
                    echo ""
                fi
                if [ -n "$truly_missing_casks" ]; then
                    gum style --foreground "$WIZ_LIGHT" "  Apps ($casks_count):"
                    echo "$truly_missing_casks" | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//' | fmt -w 56 | while IFS= read -r cline; do
                        printf '\033[38;5;%sm    %s\033[0m\n' "$WIZ_DIM" "$cline"
                    done
                    echo ""
                fi
                gum style --foreground 214 "  Install: brew bundle --file=~/.Brewfile"
            else
                echo "==> $total_missing packages not yet installed ($formulae_count CLI, $casks_count apps)"
                [ -n "$truly_missing_formulae" ] && echo "  CLI: $truly_missing_formulae" | tr '\n' ', '
                [ -n "$truly_missing_casks" ] && echo "  Apps: $truly_missing_casks" | tr '\n' ', '
                echo ""
                echo "  Install: brew bundle --file=~/.Brewfile --no-upgrade"
            fi
        fi
    fi
fi

# --- Final summary ---
echo ""
if command -v gum &>/dev/null; then
    gum style --border double --padding "1 2" --border-foreground 10 \
        "  Setup complete  "
    echo ""

    gum style --foreground "$WIZ_LIGHT" --bold "  Daily commands"
    echo ""
    printf '\033[38;5;%sm    dotfiles sync          \033[38;5;%sm%s\033[0m\n' "$WIZ_ACCENT" "$WIZ_DIM" "Apply all changes"
    printf '\033[38;5;%sm    dotfiles edit <file>   \033[38;5;%sm%s\033[0m\n' "$WIZ_ACCENT" "$WIZ_DIM" "Edit a managed file"
    printf '\033[38;5;%sm    dotfiles doctor        \033[38;5;%sm%s\033[0m\n' "$WIZ_ACCENT" "$WIZ_DIM" "Health check"
    printf '\033[38;5;%sm    dotfiles update        \033[38;5;%sm%s\033[0m\n' "$WIZ_ACCENT" "$WIZ_DIM" "Pull latest + apply"
    printf '\033[38;5;%sm    dotfiles bench         \033[38;5;%sm%s\033[0m\n' "$WIZ_ACCENT" "$WIZ_DIM" "Shell startup benchmark"
    printf '\033[38;5;%sm    dotfiles backup        \033[38;5;%sm%s\033[0m\n' "$WIZ_ACCENT" "$WIZ_DIM" "Back up config to 1Password"
    echo ""

    gum style --foreground "$WIZ_LIGHT" --bold "  Next steps"
    echo ""
    printf '\033[38;5;10m    1.\033[38;5;%sm Open a new terminal (or: exec fish)\033[0m\n' "$WIZ_DIM"
    printf '\033[38;5;10m    2.\033[38;5;%sm Sign into 1Password:  \033[38;5;%smop signin\033[0m\n' "$WIZ_DIM" "$WIZ_ACCENT"
    printf '\033[38;5;10m    3.\033[38;5;%sm Enable SSH agent: 1Password > Settings > Developer\033[0m\n' "$WIZ_DIM"
    printf '\033[38;5;10m    4.\033[38;5;%sm Run: \033[38;5;%smdotfiles doctor\033[0m\n' "$WIZ_DIM" "$WIZ_ACCENT"
    printf '\033[38;5;10m    5.\033[38;5;%sm Optional: \033[38;5;%smdotfiles watch install\033[0m\033[38;5;%sm  (S-64 background drift absorber)\033[0m\n' "$WIZ_DIM" "$WIZ_ACCENT" "$WIZ_DIM"
    echo ""
else
    echo "==> Done!"
    echo ""
    echo "Daily commands:"
    echo "  dotfiles sync         Apply all changes"
    echo "  dotfiles edit <file>  Edit a managed file"
    echo "  dotfiles doctor       Health check"
    echo "  dotfiles update       Pull latest + apply"
    echo ""
    echo "Next steps:"
    echo "  1. Open a new terminal (or: exec fish)"
    echo "  2. Sign into 1Password:  op signin"
    echo "  3. Enable 1Password SSH agent: 1Password > Settings > Developer > SSH Agent"
    echo "  4. Run: dotfiles doctor"
    echo "  5. Optional: dotfiles watch install   (S-64 background drift absorber)"
fi
