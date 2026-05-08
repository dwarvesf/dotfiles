You are maintaining a chezmoi-managed dotfiles repo. The user operates their Mac freely (installs packages, edits configs, adds API keys). Your job is to detect what changed on the machine, report it clearly, and sync approved changes back into the repo.

Packages are classified as **core** (shared across all machines, committed to repo) or **local** (this machine only, stored in `~/.Brewfile.local`). The sync workflow must ask the user to classify new packages.

## Step 1: Read context

Read `docs/sync-log.md` to understand when the last sync happened and what changed. If the file doesn't exist, this is the first sync.

## Step 2: Scan for drift

Run these detection commands in parallel where possible:

### Config drift
```bash
chezmoi status 2>/dev/null
```
Look for lines starting with ` M` (modified) or `MM` (modified both sides).

### Brew packages
```bash
# Installed but not in Brewfile or Brewfile.local
comm -23 <(brew leaves | sort) \
  <(cat <(grep '^brew "' ~/.Brewfile 2>/dev/null) \
        <(grep '^brew "' ~/.Brewfile.local 2>/dev/null) \
  | sed 's/brew "//;s/".*//' | sort -u)

# In Brewfile but not installed
comm -13 <(brew leaves | sort) <(grep '^brew "' ~/.Brewfile 2>/dev/null | sed 's/brew "//;s/".*//' | sort)
```

### Cask apps
```bash
# Installed but not in Brewfile or Brewfile.local
comm -23 <(brew list --cask 2>/dev/null | sort) \
  <(cat <(grep '^cask "' ~/.Brewfile 2>/dev/null) \
        <(grep '^cask "' ~/.Brewfile.local 2>/dev/null) \
  | sed 's/cask "//;s/".*//' | sort -u)

# In Brewfile but not installed
comm -13 <(brew list --cask 2>/dev/null | sort) <(grep '^cask "' ~/.Brewfile 2>/dev/null | sed 's/cask "//;s/".*//' | sort)
```

### VS Code extensions
```bash
# Installed but not tracked (core or local)
comm -23 <(code --list-extensions 2>/dev/null | sort) \
  <(cat ~/.config/code/extensions.txt ~/.config/code/extensions.local.txt 2>/dev/null | sort -u)

# Tracked (core) but not installed
comm -13 <(code --list-extensions 2>/dev/null | sort) <(sort ~/.config/code/extensions.txt 2>/dev/null)
```

### New fish functions (not managed by chezmoi)
```bash
# Functions on disk but not in source
comm -23 <(ls ~/.config/fish/functions/ 2>/dev/null | sort) <(chezmoi managed | grep 'fish/functions/' | xargs -I{} basename {} | sort)
```

### New SSH config fragments
```bash
# SSH config.d files not managed by chezmoi.
# Tag each one with a privacy verdict so the user can route to the right
# destination. Repo is PUBLIC (dwarvesf/dotfiles), so any fragment matching
# an infra-fingerprint pattern must NOT go to core; it belongs in a 1P
# Secure Note with the on-disk file as `*.local` (gitignored).
#
# Patterns flagged as "private":
#   - Tailscale .ts.net hostnames or any non-public hostname revealing infra
#   - Public IPv4 addresses (rough match, excluding RFC1918 / 100.64/10 / loopback)
#   - Non-standard SSH ports (Port other than 22)
#   - Identity files with purpose-revealing names (id_ed25519_<purpose>)
#
# Output format: <name> [verdict]   where verdict is "clean" or "private".
for f in $(comm -23 <(ls ~/.ssh/config.d/ 2>/dev/null | sort) \
                    <(chezmoi managed | grep 'ssh/config.d/' | xargs -I{} basename {} | sort)); do
  path=~/.ssh/config.d/$f
  verdict="clean"
  # Any of: tailnet FQDN, IP in HostName, multi-segment internal hostname,
  # purpose-revealing identity file (id_<algo>_<purpose>)
  if grep -qE '\.ts\.net|HostName +([0-9]{1,3}\.){3}[0-9]{1,3}|HostName +[a-z0-9]+(-[a-z0-9]+){1,}$|IdentityFile +.*id_[a-z0-9]+_[a-z]+' "$path" 2>/dev/null; then
    verdict="private"
  fi
  # Non-standard SSH port (anything that isn't `Port 22`)
  if grep -qE '^Port +[0-9]+' "$path" 2>/dev/null \
     && ! grep -qE '^Port +22$' "$path" 2>/dev/null; then
    verdict="private"
  fi
  echo "$f [$verdict]"
done
```

### New Claude skills (user-authored, not managed by chezmoi)
```bash
# User-authored skills under ~/.claude/skills/ that are neither tracked in
# chezmoi nor marked local. Plugin-installed skills live under
# ~/.claude/plugins/, NOT ~/.claude/skills/, so this scan is naturally
# filtered to the user's hand-rolled skills.
comm -23 <(ls ~/.claude/skills/ 2>/dev/null | sort) \
        <(cat <(chezmoi managed 2>/dev/null \
                  | grep '^\.claude/skills/' \
                  | awk -F/ '{print $3}' | sort -u) \
              <(cat ~/.config/dotfiles/skills.local 2>/dev/null | sort) \
              | sort -u)
```

### SSH backup status (notify-only, consolidated)
```bash
# Two audits batched in one bash subshell:
#   1. ~/.ssh/config.d/*.local fragments → matching 1P "SSH config: <name>" notes
#   2. ~/.ssh/* disk keys → matching 1P SSH Key items (delegated to `dotfiles ssh audit`)
#
# Why one subshell (vs two separate Bash invocations as before):
#   - `unset OP_SERVICE_ACCOUNT_TOKEN` once → both audits see the user's Private
#     vault. S-49 dual-mode: SA token can't reach Private where SSH items live.
#   - `op account get` runs once as the auth gate. ONE biometric prompt; the
#     resulting op session is reused by every later op call in this subshell.
#     Previous shape (two Bash blocks × one gate each) prompted up to 3 times
#     on session-expired runs (2 gates + ≥1 inside `dotfiles ssh audit`).
#   - `bash <<'EOF'` (heredoc): quoted EOF avoids escaping hell, AND
#     `shopt -s nullglob` makes the *.local glob expand to nothing instead of
#     erroring under zsh's default `nomatch`. Bites when CC's Bash tool
#     routes through zsh and there are zero .local fragments.
#
# Notify-only. Restoration of a private fragment is a one-line `op read` on
# fresh-machine bootstrap (see docs/guide.md > "Restore private SSH host
# fragments"). Adopting a key into 1P is interactive, never auto-run.
bash <<'EOF'
shopt -s nullglob
unset OP_SERVICE_ACCOUNT_TOKEN

# Auth gate: silent exit if op isn't signed in. Any biometric prompt fires here, once.
command -v op >/dev/null 2>&1 || exit 0
op account get >/dev/null 2>&1 || exit 0

# --- 1. SSH config fragment backup status ---
unbacked=()
for path in ~/.ssh/config.d/*.local; do
  name=$(basename "$path" .local)
  if ! op item get "SSH config: $name" >/dev/null 2>&1; then
    unbacked+=("$name")
  fi
done
if [ ${#unbacked[@]} -gt 0 ]; then
  printf 'ssh-config: %d private fragment(s) with no 1P backup: %s\n' \
    "${#unbacked[@]}" "${unbacked[*]}"
  printf "  (Notification only. To back up: op item create --category 'Secure Note' \\\\\n"
  printf "   --title 'SSH config: <name>' --vault Private \\\\\n"
  printf '   "notesPlain=$(cat ~/.ssh/config.d/<name>.local)")\n'
fi

# --- 2. SSH disk-key backup status (delegated to fish helper) ---
# Note: the fish login shell will reload OP_SERVICE_ACCOUNT_TOKEN from
# Keychain via secrets.fish.tmpl, but fish's `op` interceptor strips it
# inline (S-49) so `dotfiles ssh audit`'s op calls inherit THIS subshell's
# biometric session, no extra prompt.
if command -v fish >/dev/null 2>&1; then
  AUDIT=$(fish -l -c 'dotfiles ssh audit' 2>/dev/null)
  SUMMARY=$(echo "$AUDIT" | grep -oE '[0-9]+ of [0-9]+ disk key' | head -1)
  if [ -n "$SUMMARY" ]; then
    UNBACKED=$(echo "$SUMMARY" | awk '{print $1}')
    TOTAL=$(echo "$SUMMARY" | awk '{print $3}')
    if [ "$UNBACKED" != "0" ]; then
      echo "ssh: $UNBACKED of $TOTAL disk key(s) have no 1P backup"
    fi
  fi
fi
EOF
```

### Hardcoded secrets in fish config
```bash
# Look for set -gx with what looks like API keys (long alphanumeric strings)
grep -n 'set -gx.*[A-Za-z0-9_]\{20,\}' ~/.config/fish/config.fish ~/.config/fish/conf.d/*.fish 2>/dev/null | grep -v 'onepasswordRead\|op://' || true
```

### Secret cache status (notify-only)
```bash
# Surface any registered secret (incl. OP_SERVICE_ACCOUNT_TOKEN auto-loaded
# per S-49 dual-mode design) that has no Keychain entry yet. Silent when all
# are cached or when op is absent/unauthed.
if command -v op >/dev/null 2>&1 && op account list &>/dev/null; then
  EMPTY=$(fish -l -c 'dotfiles secret list' 2>/dev/null \
            | awk '/^  \[ empty\]/ {print $3}')
  if [ -n "$EMPTY" ]; then
    echo "secrets: registered but not cached:" $EMPTY
    echo "  (first interactive shell will biometric-prompt; run 'exec fish' to trigger now)"
  fi
fi
```

### Claude-guardrails upstream release (notify-only)
```bash
# Compare the pinned git tag in the onchange script against the most
# recent tag on dwarvesf/claude-guardrails. Purely informational: this
# check never auto-bumps. Uses tags (not GitHub Releases) because the
# project tags every version but does not always create a Release entry.
# Fail silent if the user opted out, gh is missing, or network is
# unavailable -- do not block the rest of the sync.
VARIANT=$(grep -oE 'guardrails_variant = "[^"]+"' ~/.config/chezmoi/chezmoi.toml 2>/dev/null | cut -d'"' -f2)
if [ "$VARIANT" != "none" ] && command -v gh >/dev/null 2>&1; then
  PINNED=$(grep -oE '^REF="v[0-9.]+"' home/.chezmoiscripts/run_onchange_after_claude-guardrails.sh.tmpl 2>/dev/null | cut -d'"' -f2)
  LATEST=$(gh api repos/dwarvesf/claude-guardrails/tags --jq '.[0].name' 2>/dev/null)
  if [ -n "$PINNED" ] && [ -n "$LATEST" ] && [ "$PINNED" != "$LATEST" ]; then
    echo "guardrails: pinned=$PINNED, latest=$LATEST"
  fi
fi
```

### Already-local overrides
```bash
# Show what's in .local files for context
echo "--- ~/.Brewfile.local ---"
grep -E '^(brew|cask) "' ~/.Brewfile.local 2>/dev/null | sed 's/".*/"/' || echo "(none)"
echo "--- ~/.config/code/extensions.local.txt ---"
cat ~/.config/code/extensions.local.txt 2>/dev/null || echo "(none)"
echo "--- ~/.config/fish/config.local.fish ---"
test -f ~/.config/fish/config.local.fish && wc -l < ~/.config/fish/config.local.fish | xargs echo "(lines:" | tr -d '\n' && echo ")" || echo "(not created)"
echo "--- ~/.config/tmux/tmux.local.conf ---"
test -f ~/.config/tmux/tmux.local.conf && wc -l < ~/.config/tmux/tmux.local.conf | xargs echo "(lines:" | tr -d '\n' && echo ")" || echo "(not created)"
echo "--- ~/.gitconfig.local ---"
test -f ~/.gitconfig.local && wc -l < ~/.gitconfig.local | xargs echo "(lines:" | tr -d '\n' && echo ")" || echo "(not created)"
```

## Step 2.5: Re-verify any blocker before reporting it

If a prior session's sync report appears in the conversation, **treat it as a hint, not as ground truth.** State on disk drifts between sessions; the user may have already resolved a flagged issue. Before listing any item as a blocker that requires user action (`chezmoi init`, manual signin, interactive file edit, etc.), re-derive it from current commands.

| Claim type | Re-verify with |
|---|---|
| "chezmoi init required, var X missing" | `grep '^  X = ' ~/.config/chezmoi/chezmoi.toml` - if present, the var is set, init is not needed |
| "config file Y has drifted" | `diff <(chezmoi cat ~/Y) ~/Y` - exit 0 means no drift |
| "package P is new" | re-run the `comm -23` brew/cask diff from Step 2 |
| "extension E is new" | re-run the `comm -23` extension diff from Step 2 |
| "skill S is new" | re-run the `comm -23` Claude-skills diff from Step 2 - if S is in `~/.config/dotfiles/skills.local` it is intentionally suppressed |
| anything else | re-run the underlying scan command from Step 2 |

If a prior claim no longer holds, **drop it from the report and note the discrepancy** ("prior report said X, but X is already resolved - skipping"). Never tell the user to perform interactive work without confirming the precondition currently holds.

## Step 3: Report

Present findings in plain language, grouped by category. For each category, show:
- What changed (specific names, not counts)
- Brief context if you can infer it ("ollama is probably for local LLM testing")

Use this format:

```
Dotfiles sync report - YYYY-MM-DDTHH:MM:SS @ <hostname> | rev <git-short-rev>
(Snapshot. If pasted into a later session, re-verify each blocker before acting.)

Config drift (N files):
  - path  - what changed (brief description of the diff)

New packages (N brew, N casks):
  Brew: pkg1, pkg2, ...
  Cask: app1, app2, ...

Already local (tracked in .local files):
  ~/.Brewfile.local:      brew: pkg1, ...  cask: app1, ...
  extensions.local.txt:   ext1, ...
  config.local.fish:      (N lines, or "not created")
  tmux.local.conf:        (N lines, or "not created")
  .gitconfig.local:       (N lines, or "not created")

Tip: to move items between core and local, use:
  dotfiles local promote <type> <name>   # local → core
  dotfiles local demote <type> <name>    # core → local

Guardrails upgrade available (optional):
  Pinned: v<pinned>    Latest: v<latest>
  Release notes: https://github.com/dwarvesf/claude-guardrails/releases/tag/v<latest>
  (Notification only; the pin is not auto-updated. Say "bump guardrails" if you want me to update it.)

Stale entries (N brew, N casks):
  Brew: pkg1, pkg2, ... (in Brewfile but not installed)
  Cask: app1, app2, ... (in Brewfile but not installed)

VS Code extensions:
  New: ext1, ext2, ...
  Removed: ext1, ...

New fish functions (N):
  func1, func2, ...

New SSH configs (N):
  host1 [clean]
  host2 [⚠ private] - contains infra fingerprint, must not go to core

New Claude skills (N):
  skill1, skill2, ... (user-authored, untracked)

Secrets:
  [any findings or "no issues"]

Secret cache (optional):
  Registered but not cached: VAR1, VAR2
  (Notification only. The first interactive shell on this machine will
   biometric-prompt once per secret; run 'exec fish' to trigger now.)

SSH fragment backup status (optional):
  <N> private fragment(s) with no 1P backup: <name1>, <name2>
  (Notification only. Run the op item create snippet to back up.)

SSH backup status (optional):
  <N> of <M> disk key(s) have no 1P backup: <key1>, <key2>
  (Notification only. To adopt: dotfiles ssh adopt ~/.ssh/<name>)

What would you like me to do?
```

If a category has no findings, omit it from the report.

## Step 4: Wait for decisions

Do NOT make any changes yet. Ask the user what to do. They'll respond in plain language:
- "Add the new packages"
- "Drop raycast and slack"
- "Keep btop in Brewfile even though not installed"
- "Sync the Zed config"
- "Do it all"

**For new packages/extensions, ask the user to classify:**

```
For new packages, classify as:
  [Core]  - shared across all machines (committed to repo)
  [Local] - this machine only (~/.Brewfile.local)
  [Skip]  - don't track

You can say: "all core", "all local", or classify individually
  e.g. "chrysalis and lunar are local, rest is core"
```

If the user says "do it all" without classifying, ask once: "Should new packages go to core (repo) or local (this machine)?" Default to local if the user doesn't specify.

**For new Claude skills, the same three-way classification applies** (core / local / skip):
- **core** -- generic skill useful on every machine; gets versioned in the repo
- **local** -- machine-specific or experimental; suppressed from future syncs via `~/.config/dotfiles/skills.local`
- **skip** -- decide later; resurfaces next sync

**For new SSH config fragments, classification is FOUR-way** (core / local / private / skip):
- **core** -- generic, no infra fingerprints; safe in a public repo (rare)
- **local** -- machine-specific, low-sensitivity; lives only on this machine
- **private** -- contains internal hostnames, public IPs, non-standard ports, or
  purpose-revealing key names; rename to `*.local` (gitignored) and back up to
  a 1Password Secure Note titled `SSH config: <name>`. The repo is PUBLIC; do
  NOT route flagged-private fragments to core, ever.
- **skip** -- decide later; resurfaces next sync

If the detection step flagged a fragment as `[private]`, the default
recommendation is `private`. Do not route to `core` without an explicit user
override AND verification that the file truly contains nothing sensitive.

## Step 5: Execute

Based on the user's decisions:

| Action | Method |
|--------|--------|
| Absorb config drift | `chezmoi re-add <paths>` |
| Add brew to core | Edit `home/dot_Brewfile.tmpl`, add `brew "pkg"` in correct section |
| Add brew to local | Append `brew "pkg"` to `~/.Brewfile.local` (create if needed) |
| Remove stale brew | Edit `home/dot_Brewfile.tmpl`, delete lines |
| Add cask to core | Edit `home/dot_Brewfile.tmpl`, add `cask "app"` in correct section |
| Add cask to local | Append `cask "app"` to `~/.Brewfile.local` (create if needed) |
| Remove stale casks | Edit `home/dot_Brewfile.tmpl`, delete lines |
| Add VS Code ext to core | Update `home/dot_config/code/extensions.txt` |
| Add VS Code ext to local | Append to `~/.config/code/extensions.local.txt` (create if needed) |
| Track fish functions | `chezmoi add ~/.config/fish/functions/NAME.fish` |
| Track SSH configs (core) | `chezmoi add ~/.ssh/config.d/NAME` (only after verifying NO infra fingerprint) |
| Back up SSH fragment privately | Rename file to `~/.ssh/config.d/NAME.local` (`*.local` is gitignored), then `op item create --category 'Secure Note' --title "SSH config: NAME" --vault Private "notesPlain=$(cat ~/.ssh/config.d/NAME.local)"`. Do NOT `chezmoi add`. |
| Track Claude skill (core) | `chezmoi add ~/.claude/skills/NAME` (whole directory tree, includes SKILL.md and any references/) |
| Mark Claude skill (local) | `mkdir -p ~/.config/dotfiles && echo NAME >> ~/.config/dotfiles/skills.local` (one name per line; suppressed from future drift scans, not committed) |
| Register secrets | Append to `home/.chezmoidata/secrets.toml` |
| Bump guardrails pin | Replace both `v<old>` occurrences (the `REF="v..."` line and the `ref=v...` hash comment) in `home/.chezmoiscripts/run_onchange_after_claude-guardrails.sh.tmpl` with `v<new>`. Do NOT auto-apply; the user should run `chezmoi apply` after reviewing the release notes. |
| Adopt SSH keys to 1P | Notify-only. User runs `dotfiles ssh adopt ~/.ssh/<name>` per key; the command is interactive and requires an active `op` session, so the sync skill never executes it automatically. |

When editing the Brewfile, preserve the existing section structure (base/dev/apps). Place new entries in the appropriate section.

When creating `~/.Brewfile.local` for the first time, add this header:
```ruby
# ~/.Brewfile.local - machine-specific packages (not committed to dotfiles repo)
# Sourced automatically by ~/.Brewfile via eval()
# Managed by /dotfiles-sync - classify packages as "local" during sync
```

## Step 6: Log

Append an entry to `docs/sync-log.md`, tagging the machine and distinguishing core vs local.
Get the hostname with `scutil --get ComputerName 2>/dev/null || hostname -s`.

```markdown
## [YYYY-MM-DD] sync @ <hostname>

Brewfile (core):
  - added brew: pkg1, pkg2
  - added cask: app1

Brewfile (local - ~/.Brewfile.local):
  - added cask: localapp1, localapp2

[Other categories]:
  - [what changed]

---
```

The `@ hostname` tag makes it easy to trace classification decisions back to
the machine they were made on, and spot patterns across syncs.

## Step 7: Commit

Stage all repo changes and commit with a descriptive message. Local file changes (`~/.Brewfile.local`, `extensions.local.txt`) are NOT committed since they live outside the repo.

```
chore(sync): dotfiles sync YYYY-MM-DD

[Summary of core changes by category]
Local: N packages added to ~/.Brewfile.local (not committed)
```

Then ask: "Push to remote?" Only push if the user confirms.
