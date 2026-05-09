complete -c dotfiles -f
complete -c dotfiles -n "__fish_use_subcommand" -a "edit" -d "Edit + apply + auto-commit"
complete -c dotfiles -n "__fish_use_subcommand" -a "drift" -d "Detect and re-absorb drifted files"
complete -c dotfiles -n "__fish_use_subcommand" -a "secret" -d "Manage 1Password secrets"
complete -c dotfiles -n "__fish_use_subcommand" -a "secret-guard" -d "S-62 hook: explain/test/log/mode/audit-transcripts/doctor"
complete -c dotfiles -n "__fish_use_subcommand" -a "sg" -d "S-62 hook (alias)"
complete -c dotfiles -n "__fish_use_subcommand" -a "local" -d "Manage machine-specific .local files"
complete -c dotfiles -n "__fish_use_subcommand" -a "diff" -d "Show pending changes"
complete -c dotfiles -n "__fish_use_subcommand" -a "sync" -d "Apply all changes"
complete -c dotfiles -n "__fish_use_subcommand" -a "status" -d "Show status"
complete -c dotfiles -n "__fish_use_subcommand" -a "cd" -d "Go to source dir"
complete -c dotfiles -n "__fish_use_subcommand" -a "refresh" -d "Re-download externals"
complete -c dotfiles -n "__fish_use_subcommand" -a "add" -d "Add file to chezmoi"
complete -c dotfiles -n "__fish_use_subcommand" -a "update" -d "Pull latest + apply"
complete -c dotfiles -n "__fish_use_subcommand" -a "doctor" -d "Health check"
complete -c dotfiles -n "__fish_use_subcommand" -a "bench" -d "Benchmark shell startup"
complete -c dotfiles -n "__fish_use_subcommand" -a "backup" -d "Back up config + age key"
complete -c dotfiles -n "__fish_use_subcommand" -a "encrypt-setup" -d "Set up age encryption"

# dotfiles edit accepts file paths
complete -c dotfiles -n "__fish_seen_subcommand_from edit" -a "--no-commit" -d "Skip auto-commit"
complete -c dotfiles -n "__fish_seen_subcommand_from edit" -F

# dotfiles drift
complete -c dotfiles -n "__fish_seen_subcommand_from drift" -a "--no-commit" -d "Skip auto-commit"

# dotfiles secret subcommands
complete -c dotfiles -n "__fish_seen_subcommand_from secret; and not __fish_seen_subcommand_from add rm list ls refresh" -a "add" -d "Register a secret"
complete -c dotfiles -n "__fish_seen_subcommand_from secret; and not __fish_seen_subcommand_from add rm list ls refresh" -a "rm" -d "Unregister a secret"
complete -c dotfiles -n "__fish_seen_subcommand_from secret; and not __fish_seen_subcommand_from add rm list ls refresh" -a "list" -d "Show all bindings"
complete -c dotfiles -n "__fish_seen_subcommand_from secret; and not __fish_seen_subcommand_from add rm list ls refresh" -a "refresh" -d "Clear Keychain cache, re-fetch from 1P"

# dotfiles secret refresh: --all or a registered VAR name
complete -c dotfiles -n "__fish_seen_subcommand_from refresh; and __fish_seen_subcommand_from secret" -a "--all" -d "Refresh all cached secrets"
complete -c dotfiles -n "__fish_seen_subcommand_from refresh; and __fish_seen_subcommand_from secret" \
    -a "(grep -E '^[A-Z_][A-Z0-9_]* = ' (chezmoi source-path 2>/dev/null)/.chezmoidata/secrets.toml 2>/dev/null | awk '{print \$1}')"

# dotfiles local subcommands
complete -c dotfiles -n "__fish_seen_subcommand_from local; and not __fish_seen_subcommand_from list ls promote demote edit" -a "list" -d "Show all local overrides"
complete -c dotfiles -n "__fish_seen_subcommand_from local; and not __fish_seen_subcommand_from list ls promote demote edit" -a "promote" -d "Move local → core (repo)"
complete -c dotfiles -n "__fish_seen_subcommand_from local; and not __fish_seen_subcommand_from list ls promote demote edit" -a "demote" -d "Move core → local"
complete -c dotfiles -n "__fish_seen_subcommand_from local; and not __fish_seen_subcommand_from list ls promote demote edit" -a "edit" -d "Open ~/.Brewfile.local in \$EDITOR"

# dotfiles local promote/demote types
complete -c dotfiles -n "__fish_seen_subcommand_from promote demote; and not __fish_seen_subcommand_from brew cask ext" -a "brew" -d "Homebrew formula"
complete -c dotfiles -n "__fish_seen_subcommand_from promote demote; and not __fish_seen_subcommand_from brew cask ext" -a "cask" -d "Homebrew cask (GUI app)"
complete -c dotfiles -n "__fish_seen_subcommand_from promote demote; and not __fish_seen_subcommand_from brew cask ext" -a "ext" -d "VS Code extension"

# Dynamic name completion for promote (from .local files)
complete -c dotfiles -n "__fish_seen_subcommand_from promote; and __fish_seen_subcommand_from brew" \
    -a "(grep -E '^brew \"' ~/.Brewfile.local 2>/dev/null | sed 's/^brew \"//;s/\".*//')"
complete -c dotfiles -n "__fish_seen_subcommand_from promote; and __fish_seen_subcommand_from cask" \
    -a "(grep -E '^cask \"' ~/.Brewfile.local 2>/dev/null | sed 's/^cask \"//;s/\".*//')"
complete -c dotfiles -n "__fish_seen_subcommand_from promote; and __fish_seen_subcommand_from ext" \
    -a "(cat ~/.config/code/extensions.local.txt 2>/dev/null)"

# Dynamic name completion for demote (from core files)
complete -c dotfiles -n "__fish_seen_subcommand_from demote; and __fish_seen_subcommand_from brew" \
    -a "(grep -E '^brew \"' ~/.Brewfile 2>/dev/null | sed 's/^brew \"//;s/\".*//')"
complete -c dotfiles -n "__fish_seen_subcommand_from demote; and __fish_seen_subcommand_from cask" \
    -a "(grep -E '^cask \"' ~/.Brewfile 2>/dev/null | sed 's/^cask \"//;s/\".*//')"
complete -c dotfiles -n "__fish_seen_subcommand_from demote; and __fish_seen_subcommand_from ext" \
    -a "(cat ~/.config/code/extensions.txt 2>/dev/null)"

# dotfiles secret-guard subcommands (S-62 v3.5)
set -l __sg_verbs explain test t log l tail mode m audit-transcripts at doctor d
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "explain" -d "Dry-run hook against a command"
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "test" -d "Run the spec test matrix"
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "log" -d "Tail audit log (filter with --blocks/--bypasses/--leaks/--all)"
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "tail" -d "Live-tail audit log"
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "mode" -d "Show or set hook mode (strict/warn-only/off)"
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "audit-transcripts" -d "Scan ~/.claude/projects/*.jsonl for credential patterns"
complete -c dotfiles -n "__fish_seen_subcommand_from secret-guard sg; and not __fish_seen_subcommand_from $__sg_verbs" \
    -a "doctor" -d "Health check on hook deployment"

# log filters
complete -c dotfiles -n "__fish_seen_subcommand_from log l; and __fish_seen_subcommand_from secret-guard sg" \
    -a "--blocks" -d "Only block events"
complete -c dotfiles -n "__fish_seen_subcommand_from log l; and __fish_seen_subcommand_from secret-guard sg" \
    -a "--bypasses" -d "Only bypass-marker uses"
complete -c dotfiles -n "__fish_seen_subcommand_from log l; and __fish_seen_subcommand_from secret-guard sg" \
    -a "--leaks" -d "Only Stop/PostToolUse leak detections"
complete -c dotfiles -n "__fish_seen_subcommand_from log l; and __fish_seen_subcommand_from secret-guard sg" \
    -a "--all" -d "All entries"

# mode values
complete -c dotfiles -n "__fish_seen_subcommand_from mode m; and __fish_seen_subcommand_from secret-guard sg" \
    -a "strict" -d "Default: block on rule hit"
complete -c dotfiles -n "__fish_seen_subcommand_from mode m; and __fish_seen_subcommand_from secret-guard sg" \
    -a "warn-only" -d "Log + warn but don't block"
complete -c dotfiles -n "__fish_seen_subcommand_from mode m; and __fish_seen_subcommand_from secret-guard sg" \
    -a "off" -d "Disable the hook (debug only)"
