#!/bin/bash
# One-time: install language toolchains and global tools not in Homebrew.
# Each section is idempotent.

set -eo pipefail

LIB="$HOME/.config/dotfiles/lib.sh"
# shellcheck source=/dev/null
if [ -f "$LIB" ]; then source "$LIB"; else echo "dotfiles lib not found"; exit 1; fi

section "Installing toolchains"

# Rust (via rustup)
if ! command -v rustc &>/dev/null; then
    info "Installing Rust"
    if ! rustup-init -y --no-modify-path 2>/dev/null; then
        warn "Rust: rustup-init failed" \
             "rustup may not be installed yet." \
             "brew install rustup && rustup-init -y --no-modify-path"
    fi
else
    info "Rust: already installed"
fi

# Foundry (cast, forge, anvil, chisel)
if ! command -v cast &>/dev/null; then
    info "Installing Foundry"
    if curl -L https://foundry.paradigm.xyz 2>/dev/null | bash 2>/dev/null; then
        "${HOME}/.foundry/bin/foundryup" 2>/dev/null || \
            warn "Foundry: foundryup failed" \
                 "Foundry was downloaded but setup failed." \
                 "\$HOME/.foundry/bin/foundryup"
    else
        warn "Foundry: download failed" \
             "Network error or foundry.paradigm.xyz is down." \
             "curl -L https://foundry.paradigm.xyz | bash"
    fi
else
    info "Foundry: already installed"
fi

# Global npm tools
if command -v npm &>/dev/null; then
    for pkg in ccusage markdownlint-cli2 npm-check-updates opencode-ai; do
        if ! npm list -g "$pkg" &>/dev/null; then
            info "npm: installing $pkg"
            if ! npm i -g "$pkg" 2>/dev/null; then
                warn "npm: failed to install $pkg" \
                     "Package may be unavailable or network error." \
                     "npm i -g $pkg"
            fi
        fi
    done
fi

# Global uv tools
if command -v uv &>/dev/null; then
    for pkg in llm jupyterlab jupytext gdown ouroboros-ai; do
        if ! uv tool list 2>/dev/null | grep -q "^$pkg "; then
            info "uv: installing $pkg"
            if ! uv tool install "$pkg" 2>/dev/null; then
                warn "uv: failed to install $pkg" \
                     "Package may be unavailable or network error." \
                     "uv tool install $pkg"
            fi
        fi
    done
fi

script_ok "toolchains"
