# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**LLM-maintained dotfiles for multi-machine sync.** A chezmoi-managed repo for macOS (Apple Silicon) where Claude Code is the primary maintenance interface. The `home/` directory is the chezmoi source state -- it maps to `$HOME` on the target machine. The `install.sh` script bootstraps a fresh Mac from zero.

**Default workflow:** When a user opens this repo and wants to apply, sync, update, or ask what to do with their dotfiles, suggest the `/dotfiles-sync` skill first. It handles drift detection, classification (core vs local), selective apply, and the full sync workflow.

User-facing customization flows (how to change Brewfile, secrets, editors, etc.) live in [`docs/guide.md`](docs/guide.md). When a user asks "how do I change X", point them there rather than reinventing.

## Design philosophy (read before making changes)

These principles govern the repo's architecture. Don't violate them without explicit user buy-in.

1. **The LLM does bookkeeping, the user makes decisions.** Never auto-sync, auto-promote, auto-demote, or auto-rotate without user confirmation. The whole point is that the user's hands stay on the wheel for choices; the LLM only handles mechanics.

2. **Three-way classification: core / local / skip.** Every new package, extension, or config is one of these. Core = shared across all machines (committed). Local = this machine only (gitignored `.local` files). Skip = don't track. When in doubt, ask -- don't assume "all core" or "all local."

3. **Multi-machine is a first-class use case.** Every change should consider: how does this behave when N machines run it? Per-machine state stays per-machine; shared state stays shared.

4. **Secrets live in 1Password; Keychain is a per-machine cache.** Never commit secret values. Never use iCloud Keychain for these (per-machine isolation is a feature, not a limitation). `chezmoi apply` MUST NOT trigger 1P popups -- secrets resolve lazily at shell startup via `secret-cache-read`. **Resolved secret values must never reach the session transcript** (S-45 discipline rule, S-62 enforcer hook). When you need to use a credential, follow [`docs/secret-handling-cheatsheet.md`](docs/secret-handling-cheatsheet.md): prefer the auto-loaded env var (P1: just `$CLOUDFLARE_API_TOKEN` etc.), or capture-then-use in a single Bash call (P2: `TOKEN=$(op read 'op://...'); curl -H "Authorization: Bearer $TOKEN" url`). Bare `op read`, `cat ~/.netrc`, `echo $TOKEN_VAR`, etc. are blocked. Run `dotfiles secret-guard explain '<cmd>'` to dry-run any command against the hook.

5. **Apply must be idempotent and silent.** Running `chezmoi apply` 100 times in a row should produce the same final state with zero interactive prompts (no 1P popups, no sudo prompts unless genuinely needed). If a script needs interactivity, it's likely the wrong abstraction.

6. **Sync log is the audit trail.** Every meaningful change appends an entry to `docs/sync-log.md`, hostname-tagged (`@ <hostname>`). This is more discoverable than git log for "what did I change on which machine."

## Key commands

```bash
chezmoi apply                    # Deploy all configs + run scripts
chezmoi apply --dry-run          # Preview what would change
chezmoi diff                     # Show pending diffs
chezmoi apply --refresh-externals  # Force re-download fish plugins
chezmoi managed                  # List all managed files
chezmoi edit ~/.config/fish/config.fish  # Edit a managed file
```

## Architecture

### chezmoi source directory: `home/`

chezmoi uses filename prefixes to encode target attributes:
- `dot_` → hidden file (e.g., `dot_gitconfig` → `~/.gitconfig`)
- `.tmpl` suffix → Go template, rendered at apply time
- `private_` → mode 0600
- `encrypted_` → encrypted in repo, decrypted on apply

### Secret injection (three patterns, one backend)

**1Password** is the primary backend. Three resolution patterns coexist; pick
the right one per secret:

- **Apply-time resolution** (`onepasswordRead` in Go templates) — resolves at
  `chezmoi apply`, bakes secret into rendered file. Triggers 1P popup on every
  apply. Used only where the secret must be present at file write time (e.g.,
  `dot_gitconfig.tmpl`, `dot_config/zed/settings.json.tmpl`).
- **Lazy-resolution + Keychain cache** (preferred for env vars) — the
  `secrets.fish.tmpl` emits calls to `~/.local/bin/secret-cache-read`, which
  checks macOS Keychain first and only calls `op read` on cache miss. Result:
  `chezmoi apply` never touches 1Password; only the first shell on a new
  machine triggers popups.
- **Service account token (dual-mode, S-49).** Auto-loaded into every fish
  shell via `secrets.toml` so subprocesses (Claude Code's Bash tool, scripts,
  bash one-liners) inherit bearer auth and can do ad-hoc `op read op://...`
  headlessly. **Inside interactive fish, `op` is intercepted** by
  `home/dot_config/fish/functions/op.fish`, which strips the token inline
  via `env -u OP_SERVICE_ACCOUNT_TOKEN command op` so daily commands use
  biometric and see all your vaults. Subprocesses bypass the function
  entirely. Net: full multi-vault biometric daily, headless SA-scoped
  reads in subprocesses, no per-launch wrapper needed. `with-agent-token`
  is kept as a debug escape hatch (force SA scope inside fish). Requires
  a 1Password Business/Teams plan. Prefer a dedicated `Agents` vault for
  blast-radius isolation. **Full workflow + analysis:
  [docs/1password.md](docs/1password.md).** Spec:
  [docs/specs/S-49](docs/specs/S-49-dual-mode-op-via-fish-interceptor.md);
  S-47 is amended; S-42 is superseded.

Register auto-loaded env vars via:
```
dotfiles secret add VAR "op://Vault/Item/field"   # register
dotfiles secret rm VAR                            # unregister
dotfiles secret list                              # show bindings + cache status
dotfiles secret refresh VAR                       # invalidate Keychain cache
dotfiles secret refresh --all                     # invalidate all
```

Never hand-edit `secrets.fish.tmpl` or `.chezmoidata/secrets.toml` — use the
subcommands.

**macOS Keychain**  - via `keyring` template function or runtime fish functions:
```
{{ keyring "service-name" .chezmoi.username }}
```

Template variables are prompted once during `chezmoi init` and cached:
- `.name`, `.email`  - git identity
- `.editor`  - chosen editor (`code --wait`, `zed --wait`, `nvim`, `vim`)
- `.headless`  - boolean, skips GUI apps and dev tools on servers
- `.use_1password`  - boolean, gates all 1Password sections
- `.op_account`, `.op_vault`  - only prompted if `use_1password` is true

### Core vs local packages

Packages are classified during `/dotfiles-sync`:
- **Core** - shared across all machines, committed to `home/dot_Brewfile.tmpl`
- **Local** - this machine only, stored in `~/.Brewfile.local` (never committed)

`~/.Brewfile.local` is sourced by `~/.Brewfile` via Ruby `eval()`. It uses the
same DSL (`brew "pkg"`, `cask "app"`). Similarly, `~/.config/code/extensions.local.txt`
holds machine-specific VS Code extensions. Both `.local` files are listed in
`.chezmoiignore` so chezmoi never manages them.

The sync workflow asks the user to classify each new package as core, local, or skip.
If the user says "do it all" without classifying, default to local.

**Config files with native include support:** git (`[include]`), SSH (`Include config.d/*`),
fish (`source ~/.config/fish/config.local.fish` at end of config.fish), tmux (`source-file -q`
at end of tmux.conf). All `.local` paths are in `.chezmoiignore`.

**Promoting/demoting between core and local:**
```
dotfiles local list                       # show all .local files
dotfiles local promote <type> <name>      # local → core (repo)
dotfiles local demote <type> <name>       # core → local
# type: brew, cask, ext
```
The fish function auto-commits to the repo; local file changes are never committed.

Design rationale and full cross-machine test plan:
- [docs/specs/S-35-local-pattern-and-lazy-secrets.md](docs/specs/S-35-local-pattern-and-lazy-secrets.md)
- [docs/testing.md](docs/testing.md)

### Script execution order

Scripts in `.chezmoiscripts/` run during `chezmoi apply`:

1. `run_before_aa-init.sh`  - resets apply log file (`~/.cache/dotfiles-apply.log`)
2. `run_before_ab-1password-check.sh`  - validates 1Password CLI setup (if enabled)
3. `run_onchange_before_brew-bundle.sh`  - triggers when `dot_Brewfile` content changes (sha256 hash in comment)
4. Files are deployed (including `~/.config/dotfiles/lib.sh`)
5. `run_once_after_*`  - one-time setup (fish shell, macOS defaults, mas apps, toolchains)
6. `run_onchange_after_*`  - triggers when VS Code settings/extensions or Zed config changes
7. `run_after_zz-summary.sh`  - prints styled apply summary with warnings/errors/next steps

`run_once_` scripts track execution in chezmoi's state DB and won't re-run unless the script content changes. `run_onchange_` scripts re-run when the hash comment inside them changes (chezmoi evaluates the template, hashes the output).

### External downloads: `.chezmoiexternal.toml`

Fish plugins and completions are pulled from GitHub URLs (no plugin manager). Cached with 30-day refresh. These files don't exist in `home/`  - they're defined as URLs and downloaded at apply time.

### OS-conditional: `.chezmoiignore`

The ignore file is itself a Go template. macOS-only configs (Ghostty, Zed, Brewfile) are skipped on Linux. GUI configs are skipped in GitHub Codespaces.

## Important conventions

- **Never commit secrets.** API keys go in 1Password with `op://` references in `.tmpl` files. The rendered output (with real secrets) only exists on the target machine, never in git.
- **Never echo resolved secret values** (S-45). No function, script, template, or success/error hint in this repo may print a resolved secret value to stdout or stderr. Terminal scrollback, shell history, screen recordings, and LLM tool-call transcripts all capture stdout. Reference the variable name (`"loaded into $VAR"`) or the `op://` ref; never the payload. The `secret-cache-read` helper is the one exception: its stdout is captured by `()` in `secrets.fish.tmpl`, not printed to terminal.
- **Spec status discipline (S-44).** Shipping a spec is not complete until three bookkeeping items are done: (1) frontmatter `status: done` on the spec file, (2) tick the entry in `docs/tasks.md`, (3) append a hostname-tagged entry to `docs/sync-log.md`. All three, every time. CI does not enforce this; the discipline is the rule.
- **Zed settings** (`settings.json.tmpl`) contains 5 MCP server configs with 1Password-injected API keys. When adding MCP servers, use the same `onepasswordRead` pattern.
- **VS Code settings** live in `dot_config/code/` (not the Library path). The `run_onchange_after_vscode.sh` script copies them to `~/Library/Application Support/Code/User/` at apply time.
- **Brewfile changes auto-apply**  - editing `dot_Brewfile` and running `chezmoi apply` triggers `brew bundle` automatically.
- **Fish functions** in `home/dot_config/fish/functions/` are auto-loaded by fish (one function per file, filename = function name).
- **Error message library** (`~/.config/dotfiles/lib.sh`) is sourced by all `run_*_after_*` scripts. Uses `gum log`/`gum style` for styled output with ANSI fallback. Functions: `info`, `warn "what" "why" "fix"`, `err`, `die`, `require_cmd`, `section`, `script_ok`. All warnings/errors log to `~/.cache/dotfiles-apply.log`.
- **Template guards**  - every `.tmpl` file validates required variables with `hasKey`/`fail` at the top. Missing variables produce `Fix: chezmoi init` instead of cryptic Go template errors.
- **Apply summary**  - `run_after_zz-summary.sh` prints a gum-styled status box at the end of every apply with OK/warning/failure counts, details, and actionable next steps.

## Claude Code project config

- **`.claude/settings.json`**  - project-level permissions (allow lint/verify, deny destructive) + PostToolUse hook that auto-runs shellcheck on `.sh` and `fish -n` on `.fish` after every edit.
- **`.claude/agents/verify-dotfiles.md`**  - QA subagent. Runs 5 checks: shellcheck, fish syntax, chezmoi dry-run, file existence, managed file count. Use proactively after implementing any feature.
- **`.claude/commands/implement-feature.md`**  - Slash command: `/implement-feature S-24` reads the spec, implements, verifies via subagent, fixes, commits.
- **`home/dot_claude/`**  - chezmoi-managed Claude Code user config (keybindings.json, statusline script, commands/). Deployed to `~/.claude/` on apply. Skipped on headless/Codespaces.
- **`~/.claude/settings.json`** is a two-layer construction (S-36):
  1. **Security layer** - owned by [claude-guardrails](https://github.com/dwarvesf/claude-guardrails). Installed via `home/.chezmoiscripts/run_onchange_after_claude-guardrails.sh.tmpl`, which runs `npx -y github:dwarvesf/claude-guardrails#<tag> install <variant>`. Pinned to a git tag (not an npm version) so every upstream release + tag push is installable with no npm publish step. Bumping the `REF="v0.Y.Z"` line is the only way to upgrade, by design. Variant prompted on `chezmoi init` as `.guardrails_variant` (`lite` | `full` | `none`).
  2. **Personal overlay** - `home/dot_claude/modify_settings.json` (a chezmoi `modify_` script). Reads the live file on stdin, guarantees personal fields (statusLine, learning-capture Stop hook, enabledPlugins, skipDangerousModePermissionPrompt, `permissions.defaultMode`) are present, emits on stdout. Never touches `$schema`, `permissions.deny`, or `hooks.UserPromptSubmit` - those are the guardrails layer's job. `permissions` is merged additively so `defaultMode` (ours) and `deny` (theirs) coexist. `hooks.PreToolUse` is also additive: our three managed entries are de-duped by marker, guardrails' entries (e.g. scan-commit) survive untouched.
  Both layers use additive jq merges, so they are idempotent and order-independent. Do NOT convert `modify_settings.json` back to a regular file - that would re-introduce the "whole file owned by dotfiles" conflict S-36 fixed.

## Verification rules

### Pre-action verification (before recommending interactive work)

Before asking the user to run `chezmoi init`, `op signin`, manual file edits, or any interactive command, re-verify the precondition is currently true. If a prior session's report (or pasted output) claims a blocker exists, re-derive it from current state (read the relevant config, run the diff) before parroting it. Drop claims that no longer hold and note the discrepancy. Never request interactive work for a precondition that is already satisfied -- it wastes the user's time and erodes trust in the workflow.

### Mandatory self-check (do NOT skip)

After implementing any feature from `docs/specs/S-*.md`:

1. Run the relevant verification commands (see table below)
2. If ANY check fails, fix the issue and re-run
3. Repeat until all checks pass or you've made 5 fix attempts
4. Do NOT ask the user to verify. Run verification yourself.
5. Only report back when all checks are green, or when you've hit the 5-attempt limit and need human help
6. When reporting, include the actual test output, not a summary of what you think happened

### Verification commands by file type

| File pattern | Command | What it checks |
|-------------|---------|---------------|
| `*.sh` | `shellcheck --severity=warning FILE` | Shell script lint |
| `*.fish` | `fish -n FILE` | Fish syntax check |
| `*.tmpl` | `chezmoi execute-template < FILE > /dev/null` | Template rendering |
| `home/dot_Brewfile*` | `chezmoi apply --dry-run 2>&1 \| head -50` | Brewfile validity |
| Any chezmoi file | `chezmoi apply --dry-run --verbose 2>&1 \| tail -20` | Full dry run |
| `install.sh` | `bash -n install.sh && shellcheck install.sh` | Syntax + lint |

### After every feature implementation
```bash
# 1. Lint all shell scripts
find . -name "*.sh" -not -path "./.git/*" | xargs shellcheck --severity=warning

# 2. Syntax check all fish files
find home -name "*.fish" | while read f; do fish -n "$f" || echo "FAIL: $f"; done

# 3. Dry run chezmoi
chezmoi apply --dry-run 2>&1 | tail -20

# 4. Check managed file list is not empty
test $(chezmoi managed | wc -l) -gt 10 || echo "FAIL: too few managed files"
```

### Git workflow
- Commit each feature separately with conventional commit format
- Commit message: `feat(S-XX): short description`
- Do NOT batch multiple features into one commit
- Run verification BEFORE committing, not after

### Branch naming

Format: `<type>/<short-slug>`

- `<type>`: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `ingest` (conventional-commit vocabulary)
- `<short-slug>`: 2-5 kebab-case words

Rules:
- NO owner/handle prefix (e.g. `tieubao/...`). Author is already recorded in git metadata.
- NO spec IDs in the branch name. `S-XX` belongs in the commit message and PR body, not the branch. Good: `feat/guardrails-installer`. Bad: `feat/s-36-guardrails-managed-installer`.
- NO dates, except for branches that ARE a dated batch (daily ingests: `ingest/2026-04-22`).
- Target 20-30 chars, hard cap 40. Kebab-case only.

Good examples from this repo: `feat/wireguard-tunnel-fish-functions`, `fix/no-em-dashes`, `docs/suggest-dotfiles-sync`, `feat/claude-md-personal-overlay`.
