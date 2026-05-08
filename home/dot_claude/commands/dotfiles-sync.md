You are maintaining a chezmoi-managed dotfiles repo. The user operates their Mac freely (installs packages, edits configs, adds API keys). Your job is to detect what changed on the machine, report it clearly, and sync approved changes back into the repo.

Packages are classified as **core** (shared across all machines, committed to repo) or **local** (this machine only, stored in `~/.Brewfile.local`). The sync workflow must ask the user to classify new packages.

## Step 1: Read context

Read `docs/sync-log.md` to understand when the last sync happened and what changed. If the file doesn't exist, this is the first sync.

## Step 2: Scan for drift

Run these detection commands in parallel where possible:

### Config drift
```bash
# Pre-filter: suppress always-run scripts (run_before_* / run_after_*) which
# show up on EVERY apply by design, so they are not actionable drift. Keep
# run_once_* and run_onchange_* entries as real "Pending apply" signals.
chezmoi status 2>/dev/null | while IFS= read -r line; do
  code="${line:0:2}"
  path="${line:3}"
  if [[ "$path" == .chezmoiscripts/* ]]; then
    base="${path#.chezmoiscripts/}"
    src=""
    for f in home/.chezmoiscripts/*; do
      fn="${f##*/}"
      if [[ "$fn" == *"_$base" || "$fn" == *"_$base.tmpl" ]]; then
        src="$fn"; break
      fi
    done
    case "$src" in
      run_before_*|run_after_*) continue ;;  # always-runs, not drift
    esac
  fi
  printf '%s\n' "$line"
done
```

`chezmoi status` prints `XY PATH` where X = source state since last apply, Y = destination state since last apply. Interpret each code into a sync direction so the report can group correctly:

| Code | Meaning | Direction | Report bucket |
|---|---|---|---|
| `A ` | source added, dest unchanged | apply creates on dest | **Pending apply** (`+`) |
| `M ` | source modified | apply updates dest | **Pending apply** (`~`) |
| `D ` / `R ` | source removed | apply deletes from dest | **Pending apply** (`-`) |
| ` A` | dest gained a file, source unaware | absorb or ignore | **Drift to absorb** (`+`) |
| ` M` | dest modified since last apply | needs `chezmoi re-add` | **Drift to absorb** (`~`) |
| ` D` / ` R` | dest deleted, source still has it | restore on apply, or `chezmoi forget` | **Drift to absorb** (`-`) |
| `MM` / `AM` | both sides changed | needs manual reconcile | **Conflict** (`‼`) |

For every `MM` and any ambiguous case, **re-derive direction** with `bash -c 'diff <(chezmoi cat ~/PATH) ~/PATH'` before reporting. Don't trust the code alone.

**Special case: `.chezmoiscripts/<name>` entries.** chezmoi reports `R` here for any script that *will run* on the next apply, not for drift. Resolve via the source filename's prefix in `home/.chezmoiscripts/`:

| Source prefix | Behavior | Report as |
|---|---|---|
| `run_before_*` | runs before every apply, always | **suppress** (handled by pre-filter above) |
| `run_after_*` | runs after every apply, always | **suppress** (handled by pre-filter above) |
| `run_once_*` | only shows `R` if not yet recorded in state DB | **Pending apply** (`apply` will execute + record) |
| `run_onchange_*` | only shows `R` when rendered hash differs | **Pending apply** (`apply` will execute + re-record) |

Never report a `.chezmoiscripts/*` entry under "Drift to absorb." Scripts don't deploy files; they execute. The right verb is "pending apply," and the action is `chezmoi apply`.

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
# Look for `set -gx` lines with long alphanumeric values that resemble API
# keys. Wrapped in a bash subshell with `shopt -s nullglob` so an empty
# conf.d/ doesn't trigger zsh's `nomatch` error when CC's Bash tool routes
# through zsh (same class of bug fixed for the SSH backup audit).
bash <<'EOF'
shopt -s nullglob
files=( ~/.config/fish/config.fish ~/.config/fish/conf.d/*.fish )
[ ${#files[@]} -gt 0 ] || exit 0
grep -n 'set -gx.*[A-Za-z0-9_]\{20,\}' "${files[@]}" 2>/dev/null \
  | grep -v 'onepasswordRead\|op://' || true
EOF
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
grep -E '^(brew|cask) "' ~/.Brewfile.local 2>/dev/null | sed -E 's/^([a-z]+ "[^"]+").*$/\1/' || echo "(none)"
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

Present findings in a **delta-inspired, color-coded, grouped-by-direction layout** so the user can scan quickly. Visual references: git-`delta`'s side-by-side responsive diff (commit-header block on top, file pills `▮`, `@@` hunk separators, **collapses to unified on narrow screens**) and renamed-file display (`old → new` arrows). The report renders as markdown in Claude Code's UI: ANSI escapes inside code fences are stripped, so use **emoji as semantic color**, **Unicode block characters (`▮ ▌ ▍`) for visual weight**, **arrow `→` for transitions**, and **markdown horizontal rules** as hunk separators. ANSI is only useful for a terminal-piped fallback, not the default render path.

### 3a. Width detection (responsive layout)

Detect terminal width with a small cascade — Claude Code's Bash tool runs without a TTY, so `tput cols` returns 80 there even when the user's actual UI is wider:

```bash
COLS=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
```

- `COLS >= 140` → **two-column layout** *eligible* (Pending apply | Drift to absorb side-by-side, manually aligned inside one fenced code block — see 3e)
- `COLS  < 140` → **single-column layout** (sections stacked vertically inside fenced code blocks — see 3d)

**Balance check (mandatory before choosing two-column):** count rows on each side. Two-column only earns its keep when both sides are populated *and* roughly balanced.

```
LEFT  = rows in "Pending apply"
RIGHT = rows in "Drift to absorb"
RATIO = max(LEFT, RIGHT) / max(min(LEFT, RIGHT), 1)
```

- `RATIO >= 4` → **fall back to single-column.** A 19/2 split (ratio 9.5) wastes ~85% of the right column's real estate; the visual scan cost beats any side-by-side benefit.
- `RATIO < 4` AND `min(LEFT, RIGHT) >= 3` → use two-column.
- Otherwise → single-column.

If both signals are unreliable (non-TTY, no `$COLUMNS`), prefer single-column. A user can always say "narrow" / "wide" to override; ask once if unsure, then remember the choice for the rest of the session.

### 3a.1 No markdown tables — ever

**Hard rule: do NOT use markdown tables (`| col | col |`) anywhere in the report.** Claude Code's renderer draws heavy cell borders around every row, which destroys the dense delta-style look the user wants. Use these alternatives instead:

| ❌ Don't do this | 🍃 Do this instead |
|---|---|
| `| 🟢 + foo | bar |` two-col table | one fenced code block with manual `│`-separated columns |
| `| Bucket | Items |` for untracked-installs | indented list under a heading: `🔴▮ superseded:` then a blank-line-separated bullet list |
| `| Check | Status |` for notify-only | indented `key:` `value` pairs, key padded to a consistent width |
| `| File | Contents |` for already-local | one fenced code block with manual alignment, or `→`-prefix lines |

The (small) table you're reading right now is OK because **it's instructional, not part of the report**. The runtime report has zero tables.

### 3b. Visual vocabulary

**Markers** (lead each line, mapped to semantic colors via emoji indicator):

| Marker | Emoji | Meaning | Mood |
|---|---|---|---|
| `+` | 🌿 | added — exists on one side, missing on other | growth |
| `-` | 🔻 | removed / deprecated — superseded or pending deletion | down-shift |
| `~` | 🌀 | modified — both have it, content differs | drift |
| `‼` | ⚠️ | conflict — both sides changed independently | attention |
| `·` | ⚪ | notify-only — informational, no action expected | quiet |
| (bucket) | 👾 | classify — needs a core/local/skip decision | unknown |

**Status icons** (used in the Notify-only section, one per check):

| Icon | Meaning |
|---|---|
| 🍃 | check passed / all good |
| ⚠️ | non-blocking warning, action recommended |
| ❌ | failure / urgent action needed |

**Sub-glyphs** (used inside fenced sections for layout):
- `▮` colored pill, used for `⚪▮ <path>` rows in Already-local and bucket labels in Untracked
- `▸` sub-bullet, used for nested items under a row (e.g. `▸ cask (N): item · item`)
- `•` bullet, used for grouped item lists inside Untracked buckets
- `✗` missing/empty marker, used in Already-local for files not yet created

**Row format (strict, compact):**

```
<emoji> <marker> <padded-path>  <description> [tag]
```

- `<emoji>` is the marker color (`🟢🔴🟡🟠⚪`). Single space after.
- `<marker>` is the ASCII glyph (`+ - ~ ‼ ·`). Single space after.
- `<padded-path>` is the path padded to the longest path *in this section*, capped at 46 chars; truncate longer paths from the front with `…`.
- **Two spaces** between padded-path and description (no `⇒` glyph — wastes a column).
- `<description>` is free-text, **≤40 chars**. Use `→` only for value transitions: `python 3.12.10 → 3.12.13`. Never use `+` / `-` inside the description (the row marker owns those glyphs); say `adds Host github.com` instead of `+ Host github.com`.
- `[tag]` immediately after the description, **single space gap, NOT right-aligned to a column**. Right-aligned tag columns force long pad-stretches that read as visual noise. Inline is denser and the bracket itself is its own visual delimiter.

**Examples (correct):**

```
🌿 + .claude/skills/extract-workflow/  PR #76 (multi-machine-op) [new]
🌀 ~ ~/.tool-versions                  python 3.12.10 → 3.12.13 [mod]
🌀 ~ ~/.ssh/config                     adds Host github.com block [mod]
⚠️ ‼ ~/.config/zed/settings.json       cli_default: existing → new [conflict]
🌀 ~ ~/.Brewfile                       +4 brews (agent-browser, opencode, …) [mod]
```

**Wrong — do not emit:**

```
🟢 + .claude/skills/foo/  ⇒  PR #76                                                [new]   ← right-pad before tag wastes cells
🟡 ~ .Brewfile  adds agent-browser, opencode, ollama, playwright-cli [mod]                ← description >40 chars; will wrap
```

**Description-length rule:** if the natural description exceeds 40 chars (e.g. listing 4 added Brewfile entries), summarize as a count plus `…`: `+4 brews (agent-browser, opencode, …)`. The full list belongs in the section's *footer line* (see 3d) or in commit message at apply time, not on the diff row.

The ASCII marker (`+ - ~ ‼`) is kept alongside the emoji so structure survives copy-paste into a terminal that strips emoji. Both signals live in the same 4-cell prefix budget.

**Bucket pills** (used inside Untracked-installs and Already-local sections) — `🔻 superseded:` / `👾 classify:` / `👾 casks:` / `⚪▮ <path>` for already-local file rows. Don't use on per-row diff entries — the leading marker emoji already conveys color.

**Tags** (bracketed, end of line; rendered bold via markdown `**[tag]**`):

| Tag | Meaning |
|---|---|
| `[new]` | brand-new untracked file or package |
| `[mod]` | modified vs other side |
| `[del]` | deleted from one side |
| `[conflict]` | both sides changed independently |
| `[local]` | already routed to a `.local` override |
| `[stale]` | listed in `~/.Brewfile` but not installed |
| `[superseded]` | deprecated tool with a modern replacement (uninstall candidate) |
| `[private]` | SSH fragment with infra fingerprint — never goes to core |
| `[clean]` | SSH fragment with no fingerprint — safe for core |
| `[pseudo-stale]` | apparent staleness that resolves on next `chezmoi apply` |

**Section dividers (inside the fenced block, format `─── <emoji> Title — context ───`):**

| Section | Divider emoji | Direction |
|---|---|---|
| Pending apply (repo → machine) | 🌿 | apply |
| Drift to absorb (machine → repo) | 🌀 | re-add |
| Conflict (both sides) | ⚠️ | reconcile |
| Untracked installs | 👾 | classify |
| Stale Brewfile entries | 🔸 | cleanup |
| Already local | ⚪ | informational |
| Notify-only | ⚪ | informational |
| Recommended order | ✨ (markdown heading, outside the fenced block) | action plan |

### 3c. Header block (compact, 2 lines)

Start the report with a tight 2-line summary inside a fenced code block. No multi-line styled box — that wastes vertical space and the CC renderer pads it further.

```
sync 2026-05-08T20:35  @ Mac mini  rev c5e7009  narrow
🌿 19 pending  ·  🌀 2 drift  ·  ⚠️ 2 conflict  ·  👾 21+5 untracked  ·  ⚪ 1/2 ssh-key
```

If a count is zero, omit it entirely (don't emit `🌿 0 pending`). The line collapses gracefully when little has changed. Emojis here mirror the section-divider palette in 3b.

### 3d. Single-column layout (default, COLS < 140)

**One fenced code block for the entire diff body.** Section dividers are `─── 🟢 Title ───` lines *inside* the block, not markdown `###` headings. This eliminates the unavoidable blank line CC's renderer inserts between an `###` heading and a fenced block — the user explicitly does not want that gap.

After the diff body, the only markdown headings allowed are `### ✨ Recommended order` (because it's an action list, not a diff) and the trailing tip. Everything else is in the single block.

````markdown
[header block from 3c — already inside its own code fence]

*(Snapshot. Re-verify each blocker before acting.)*

```
─── 🌿 Pending apply (repo → machine) — chezmoi apply ───
🌿 + .claude/skills/extract-workflow/  PR #76 [new]
🌿 + .claude/hooks/machine-banner/…    SessionStart hook [new]
🌀 ~ .claude/CLAUDE.md                 +211 lines (machines table) [mod]
🌀 ~ .Brewfile                         +4 brews (agent-browser, …) [mod]
🔻 - .chezmoiscripts/old.sh            will be removed [del]

─── 🌀 Drift to absorb (machine → repo) — chezmoi re-add ───
🌿 + ~/.config/fish/functions/foo.fish  untracked [new]
🌀 ~ ~/.ssh/config                      adds Host github.com block [mod]
🌀 ~ ~/.tool-versions                   python 3.12.10 → 3.12.13 [mod]

─── ⚠️ Conflict (both sides changed) — manual reconcile ───
⚠️ ‼ ~/.claude/settings.json   source adds SessionStart; live drifted [conflict]

─── 👾 Untracked installs — classify: core / local / skip ───
🔻 superseded (likely brew uninstall — modern equivalents already in core):
   • htop · hub · pipx · rbenv · ruby · rust · mosh
   • the_silver_searcher · youtube-dl · z · zsh
👾 classify (core / local?):
   • apfel · coreutils · gitup · restic · subversion · tailscale · typescript · yarn
   • hashicorp/tap/terraform · steipete/tap/remindctl
👾 casks (likely renames / auto-deps):
   • codex-app · google-cloud-sdk · microsoft-auto-update · ollama-app · zen

─── 🔸 Stale Brewfile entries ───
🌀 ~ ~/.Brewfile   [8 phantom]   ffmpeg · go · librsvg · node · protobuf ·
                                  ripgrep · sqlite · terraform
                   auto-resolves on next chezmoi apply [pseudo-stale]

─── ⚪ Already local ───
⚪▮ ~/.Brewfile.local           ▸ cask (8): chrysalis · disk-inventory-x · lunar ·
                                            monitorcontrol · skype · warp · tor-browser · meetingbar
                                ▸ brew (2): sentencepiece · lume
⚪▮ extensions.local.txt        ✗ empty
⚪▮ config.local.fish           ✗ not created
⚪▮ tmux.local.conf             ✗ not created
⚪▮ .gitconfig.local            ✗ not created

─── ⚪ Notify-only ───
🍃 guardrails       pinned v0.3.8 → latest v0.3.8  ·  up-to-date
🍃 secrets cache    all cached
⚠️  ssh keys         1/2 disk key(s) without 1P backup
                    → dotfiles ssh adopt ~/.ssh/<name>
🍃 hardcoded        no issues
```

### ✨ Recommended order

1. `chezmoi apply` — deploys the N pending entries
2. Reconcile the M conflicts — diff each, pick a side
3. `chezmoi re-add` for K drift items — absorb local edits
4. Decide on the J untracked brews — uninstall vs classify
5. (interactive) Adopt SSH key into 1P

**Tip** — `dotfiles local promote/demote <type> <name>` to move between core ↔ local

What would you like me to do?
````

**Section divider rules:**
- Format: `─── <emoji> <Title> — <subcommand-or-context> ───` (with one space inside each `───` cap).
- **One blank line BEFORE each divider, except the very first divider in the fenced block.** Gives sections breathing room. NO blank line *after* the divider — the first row sits flush below the divider.
- The divider's emoji = the section's primary color (per 3b table).
- Sections appear in the priority order from 3b's section table (Pending apply → Drift → Conflict → Untracked → Stale → Already local → Notify-only).

**Bottom-half decoration rules** — these sections are all-informational; without explicit decoration they read as a flat wall of text. Apply:

- **Untracked installs** — bucket pill (🔻/👾) + indented `•` bullets, items broken into 1-2 visual rows per bucket. Don't dump 11 names on a single line.
- **Stale Brewfile entries** — boxed count `[N phantom]` after the path provides visual weight; description follows on next line, indented.
- **Already local** — every row gets a `⚪▮` pill prefix matching the diff-row format. Sub-buckets (cask/brew under `~/.Brewfile.local`) use `▸` with a count: `▸ cask (8):`. Missing files get a `✗` marker (red-style "not present"). Aligned column for the file name.
- **Notify-only** — every row leads with a status icon: `🍃` pass, `⚠️` warning, `❌` failure. The icon answers "should I look at this?" before the text does. Multi-line entries (e.g. follow-up command for an action) indent under the parent row.

### 3e. Two-column layout (COLS >= 140 *and* balance check passes)

When width allows AND `RATIO < 4`, render Pending apply and Drift to absorb side-by-side inside the single fenced code block, using `│` (U+2502) as separator. **Do not use markdown tables.**

````markdown
[header block from 3c]

*(Snapshot. Re-verify each blocker before acting.)*

```
─── 🟢 Pending apply — chezmoi apply ──────────────  │  ─── 🔵 Drift to absorb — chezmoi re-add ───
🟢 + .claude/skills/extract-workflow/  PR #76 [new]   │  🟡 ~ ~/.ssh/config         adds github.com [mod]
🟢 + .claude/hooks/machine-banner/…    banner [new]   │  🟡 ~ ~/.tool-versions      3.12.10 → 3.12.13 [mod]
🟡 ~ .claude/CLAUDE.md                 +211 ln [mod]  │
🟡 ~ .Brewfile                         +4 brews [mod] │
─── 🟠 Conflict — manual reconcile ─────────────────────────────────────────────────────────────
🟠 ‼ ~/.claude/settings.json    source adds SessionStart; live drifted [conflict]
🟠 ‼ ~/.config/zed/settings.json   cli_default: existing → new [conflict]
─── 🟣 Untracked installs — classify: core / local / skip ──────────────────────────────────────
🔴▮ superseded:  htop · hub · pipx · rbenv · ruby · rust · the_silver_searcher · ...
🟣▮ classify:    apfel · coreutils · gitup · ...
🟣▮ casks:       codex-app · google-cloud-sdk · ...
[remaining sections continue full-width below the two-column band]
```
````

The two-column band ends at the first `─── ... ───` divider whose section is full-width-only (Conflict, Untracked, Already local, Notify-only). After that point, lines run edge-to-edge — no `│` separator.

**Column-alignment rules for the two-column block:**
- **Compute** left-column width once: `max(len(line) for line in left_rows)` clamped to `[60, 80]`. Apply that exact width to every left row via right-pad with spaces. Same for right column (clamp `[40, 60]`).
- Right column starts at column = left-width + 3 (`│` plus a single padding space on each side).
- Truncate paths from the front with `…` if they would overflow (e.g. `…/fish/functions/with-agent-token.fish`); never wrap inside a row.
- If one column has fewer rows than the other, leave the shorter column blank but emit the `│` column-divider on every row so the vertical line stays continuous.
- The header row (with section titles + commands) gets one blank line below it — that blank line is the visual "hunk separator" (mirrors `delta`'s `@@`).
- **Run the balance check first** (3a). If `RATIO >= 4`, do NOT use this layout — fall back to single-column even if `COLS >= 140`.

**Layout rules (both modes):**
- Always emit the compact 2-line header block (3c) with timestamp, hostname, short rev, layout choice, and section counts. It's the audit anchor.
- The diff body is **one single fenced code block** containing all sections separated by `─── 🟢 Title ───` dividers (per 3d). No markdown `###` headings inside the diff body — they introduce unwanted blank lines.
- **Never use markdown tables.** Per 3a.1: tables get a heavy grid in CC's renderer that destroys the dense delta look.
- Empty section → omit the divider line entirely; don't emit `─── 🟢 Pending apply ───` followed by nothing.
- Path display: full target (`~/...`) for drift, repo-relative for source.
- **Tags are mandatory** on every row (per 3b), inline, single space after the description. **Do not right-align** — pad-stretches read as visual noise.
- **Collapse repetition.** When ≥5 consecutive rows share the same description (e.g. ten skills all from `PR #76`), emit one summary row + indented bullet list:
  ```
  🟢 + 10 skills from PR #76 (multi-machine-op) [new]
       browser-tool-selection · cashflow-close · cloudflare-tool-selection ·
       doc-compaction · extract-workflow · incident-workflow · ingest-to-wiki ·
       playwright-record · reconcile-properties · vn-contract-format
  ```
- **One blank line BEFORE each section divider** (except the first), zero blank lines after. This is the visual hunk separator — sections breathe but rows sit pixel-tight under their divider.
- "Recommended order" is mandatory when ≥3 direction sections exist; otherwise optional.
- Tip line + `What would you like me to do?` always go at the very end (outside any code fence so they render as prose).

**Tip** — to move items between core and local:
  - `dotfiles local promote <type> <name>` — local → core
  - `dotfiles local demote <type> <name>` — core → local

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
