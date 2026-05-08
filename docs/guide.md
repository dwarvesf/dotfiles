# User guide

Everything you need to use and customize this dotfiles setup. The
[README](../README.md) covers the pitch and quick start; this guide
covers how it all works and how to make it yours. For the general
LLM-maintained dotfiles pattern, see [llm-dotfiles.md](llm-dotfiles.md).

---

## 1. The LLM workflow

The primary way to maintain this repo is to ask Claude.

Run `/dotfiles-sync` in Claude Code (or just say "catch up with my
dotfiles"). Claude scans your machine across 11 dimensions: config
drift, brew packages, casks, VS Code extensions, fish functions, SSH
configs, user-authored Claude skills (`~/.claude/skills/`), secrets,
and more. It reports what changed in plain language and waits for
your instructions.

```
You:    /dotfiles-sync
Claude: Config drift: Zed settings (2 new MCP servers)
        New packages: ollama, rclone, pandoc
        Stale: raycast, slack (not installed)
        What should I do?
You:    sync everything, drop raycast and slack
Claude: Done. 1 commit. Push?
You:    push
```

Every sync is logged in `docs/sync-log.md`. Claude reads it at the
start of each session for context ("last sync was 2 weeks ago, you
added ollama").

The `/dotfiles-sync` command is installed to `~/.claude/commands/`
during `chezmoi apply`, so it works from any directory in Claude Code,
not just the dotfiles repo. If it's missing, run `chezmoi apply` to
deploy it.

### Free-form asks (beyond `/dotfiles-sync`)

`/dotfiles-sync` is the batched scan-and-sync flow. For any single change,
just describe it to Claude in plain language — Claude knows where each piece
of the repo lives and will make the edit in the right place, apply, verify,
and offer a commit:

> "Add `ollama` to the Brewfile as local."
>
> "Rotate my OpenAI key — I just generated a new value."
>
> "Prefer Biome over Prettier+ESLint in my Claude tech stack rules."
>
> "Add an SSH host called `staging` pointing at 10.0.1.50."
>
> "Bump claude-guardrails to v0.3.9 and commit."

This is usually faster than looking up the right file or command. The
manual commands in the sections below are fallbacks for when Claude isn't
available (offline, SSH'd into a server, quick one-off), or when you want
to know what's actually happening under the hood.

### Core vs local packages

When syncing, Claude asks you to classify each new package:

| Classification | Where it goes | Committed? | Installed on all machines? |
|---------------|--------------|-----------|--------------------------|
| **Core** | `~/.Brewfile` (from template) | Yes | Yes |
| **Local** | `~/.Brewfile.local` | No | This machine only |
| **Skip** | Nowhere | No | N/A |

`~/.Brewfile.local` is automatically sourced by `~/.Brewfile` and uses
the same syntax (`brew "pkg"`, `cask "app"`). It is never committed to
git or managed by chezmoi. The same pattern works for VS Code extensions
via `~/.config/code/extensions.local.txt`.

**Examples of local packages:** hardware-specific tools (`chrysalis` for
Keyboardio, `lunar` for display brightness), rarely-used apps (`skype`),
disk utilities (`disk-inventory-x`).

**Manual local management** via the `dotfiles local` subcommand:
```bash
dotfiles local list                        # show everything in .local files
dotfiles local edit                        # open ~/.Brewfile.local in $EDITOR
dotfiles local promote cask chrysalis      # move from local to core (shared repo)
dotfiles local demote brew sentencepiece   # move from core to local
dotfiles local promote ext openai.chatgpt  # VS Code extension
```

Promote/demote auto-commits core changes. Tab completion suggests the exact
packages available to move in each direction.

**Other config files with machine-specific overrides:**

| Config | Local file | Include mechanism |
|--------|-----------|-------------------|
| Brew/cask | `~/.Brewfile.local` | Ruby `eval()` in `.Brewfile` |
| VS Code | `~/.config/code/extensions.local.txt` | Read by apply script |
| Fish | `~/.config/fish/config.local.fish` | `source` at end of config.fish |
| Tmux | `~/.config/tmux/tmux.local.conf` | `source-file -q` at end of tmux.conf |
| Git | `~/.gitconfig.local` | `[include] path = ...` |
| SSH | `~/.ssh/config.d/*` | `Include config.d/*` |
| Claude skills | `~/.config/dotfiles/skills.local` (one skill name per line) | Read by `/dotfiles-sync` to suppress drift detection |

All `.local` paths are in `.chezmoiignore`, so `chezmoi add` won't accidentally
track them.

---

## 2. How chezmoi works

### The two layers

chezmoi keeps two copies of every config file:

| Layer | Location | Contains |
|-------|----------|----------|
| **Source** (repo) | `~/.local/share/chezmoi/home/` | Templates, `op://` refs, chezmoi prefixes |
| **Target** (machine) | `$HOME` | Rendered files with real values |

You edit the source. chezmoi renders templates and copies the result to
your home directory. This is a one-way flow: source to target.

<p align="center">
  <img src="dotfiles_chezmoi_model.svg" alt="chezmoi model: source to target" width="680">
</p>

**Why two layers?** The source can live in a public git repo because it
never contains real secrets  - only `op://` references. The target has
your actual API keys, but it's never committed.

Here's the full bootstrap flow when you first install:

<p align="center">
  <img src="dotfiles_bootstrap_flow.svg" alt="Bootstrap flow" width="680">
</p>

### Where things live

```
~/dotfiles/                          ← the repo (git clone location)
├── home/                            ← chezmoi source state
│   ├── dot_gitconfig.tmpl           ← becomes ~/.gitconfig
│   ├── dot_config/
│   │   ├── fish/
│   │   │   ├── config.fish.tmpl     ← shell config
│   │   │   ├── functions/           ← one file per function
│   │   │   ├── completions/         ← tab completions
│   │   │   └── conf.d/              ← auto-sourced snippets
│   │   ├── ghostty/config           ← terminal config
│   │   ├── starship.toml            ← prompt config
│   │   ├── tmux/tmux.conf           ← multiplexer config
│   │   ├── code/                    ← VS Code settings
│   │   └── zed/                     ← Zed settings
│   ├── dot_Brewfile.tmpl            ← Homebrew packages
│   ├── .chezmoidata/secrets.toml    ← secret registry (op:// refs)
│   └── .chezmoiscripts/             ← automation scripts
├── docs/                            ← this guide, specs, ADRs
└── install.sh                       ← bootstrap script
```

Naming: `dot_` becomes `.`, `.tmpl` means "render this template",
`private_` sets mode 0600.

---

### What happens on install

<p align="center">
  <img src="dotfiles_bootstrap_flow.svg" alt="Bootstrap flow" width="680">
</p>

1. Installs Homebrew (if missing)
2. Installs chezmoi + runs setup wizard (name, email, editor, headless, 1Password)
3. Deploys all config files to `$HOME`
4. Runs `brew bundle` (~80 packages + casks)
5. Mac App Store apps via `mas`
6. macOS defaults (Dock, Finder, keyboard, trackpad, screenshots)
7. Sets Fish as default shell
8. Installs toolchains (Foundry, Rust, npm/uv), VS Code extensions
9. Verifies key files were deployed

**Install flags:**
- `./install.sh --check` -- dry-run, validates without applying
- `./install.sh --force` -- teardown and reinit from scratch
- `./install.sh --config-only` -- deploy config files only, skip brew/mas/defaults

**Adopt on an existing Mac:**
```bash
cd ~/dotfiles && ./install.sh --config-only
```
Then set Fish as default: `chsh -s /opt/homebrew/bin/fish`

**Bootstrap without git** (fresh Mac, no Xcode CLT):
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply dwarvesf
```

---

## 3. Your first 30 minutes

You just ran `install.sh`. Here's what's on your machine now.

### Shell: Fish

Your default shell is now [Fish](https://fishshell.com/). It differs
from bash/zsh in a few ways:

- **Autosuggestions**  - type a few characters, Fish suggests from history
  in gray. Press `→` to accept.
- **Tab completion**  - press `Tab` for rich completions with descriptions.
- **No `.bashrc`**  - config lives at `~/.config/fish/config.fish`.
- **Abbreviations, not aliases**  - type `gs` then space, it expands to
  `git status`. Your abbreviations:

| Category | Abbreviations |
|----------|--------------|
| Git | `g` `gs` `gd` `gl` `gp` `gc` `gco` `gpr` |
| Navigation | `ls` `l` `ll` `la` `lt` `..` `...` |
| Modern replacements | `cat`→bat `top`→btop `du`→dust `df`→duf `ps`→procs |
| Tmux | `tx` `tml` `tma` `tmk` |
| Kubernetes/Docker | `k` `k9` `d` `dc` |

Fish plugins (installed without a plugin manager, via direct download):

| Plugin | What it does |
|--------|-------------|
| **autopair** | Auto-closes brackets, quotes, parentheses |
| **done** | Desktop notification when a long command finishes |
| **sponge** | Removes failed commands from history |
| **async-prompt** | Keeps the prompt responsive while git info loads |

### Terminal: Ghostty

[Ghostty](https://ghostty.org/) is your terminal. Key settings:

- **Font**: SauceCodePro Nerd Font, size 12
- **Theme**: base16-eighties-dark (switch with `ghostty-theme N`)
- **Quick toggle**: `Cmd+`` brings up the terminal from anywhere
- **Splits**: `Cmd+Shift+Enter` (right), `Cmd+Shift+-` (down)
- **Navigate splits**: `Cmd+Alt+Arrows`

### Prompt: Starship

[Starship](https://starship.rs/) shows: directory, git branch/status,
language versions (Go, Python, Node, Rust), cloud context (AWS, k8s),
and command duration (if >3s). Green arrow = last command OK, red = error.

### Editors

Your editor was set during install (`chezmoi init`). VS Code and Zed
both have managed settings and extensions. MCP servers in Zed are
pre-configured with 1Password-injected API keys.

### Verify everything works

```fish
dotfiles doctor
```

This checks: chezmoi installed, fish is default shell, Homebrew, 1Password,
key config files exist, git identity set, CLI tools present, no drift.

---

## 4. Manual commands (offline fallback)

### Editing any config

Use `dotfiles edit` (dotfile edit) for all config changes. It edits the source,
applies, and auto-commits in one step:

```fish
dotfiles edit ~/.config/fish/config.fish
```

<p align="center">
  <img src="dotfiles_dfe_workflow.svg" alt="dfe workflow" width="680">
</p>

Pass `--no-commit` to skip the auto-commit.

### Adding a Homebrew package

Don't run `brew install` directly  - that installs locally but doesn't
update the Brewfile, so your next machine won't have it.

```fish
dotfiles edit ~/.Brewfile    # add the line, save, brew bundle runs automatically
```

<p align="center">
  <img src="dotfiles_workflow_brew.svg" alt="Homebrew workflow" width="680">
</p>

### Handling drift

If you (or an app) edited a deployed file directly, `dotfiles drift` detects and
fixes it:

```fish
dotfiles drift    # shows drifted files, prompts, re-absorbs into source, commits
```

<p align="center">
  <img src="dotfiles_dfs_workflow.svg" alt="dfs workflow" width="680">
</p>

### Changing a config: two paths

<p align="center">
  <img src="dotfiles_workflow_config.svg" alt="Config change: dfe vs direct edit" width="680">
</p>

### The `dotfiles` CLI

For everything beyond editing, use the `dotfiles` wrapper:

| Command | Alias | Abbr | What it does |
|---------|-------|------|-------------|
| `dotfiles edit <path>` | `e` | `de` | Edit + apply + auto-commit |
| `dotfiles drift` | | `dd` | Detect and re-absorb drifted files |
| `dotfiles secret <cmd>` | | | Manage 1Password secrets (add/rm/list) |
| `dotfiles diff` | `d` | | Show pending changes |
| `dotfiles sync` | `s` | `ds` | Apply all changes |
| `dotfiles update` | `u` | `dfu` | Pull latest + apply |
| `dotfiles status` | `st` | | Managed file count + pending diffs |
| `dotfiles cd` | | | Go to chezmoi source directory |
| `dotfiles refresh` | `r` | | Re-download fish plugins |
| `dotfiles add <path>` | `a` | | Add a new file to chezmoi |
| `dotfiles doctor` | | | Health check |
| `dotfiles bench` | | | Benchmark shell startup time |
| `dotfiles backup` | | | Back up config + age key to 1Password |
| `dotfiles encrypt-setup` | | | Set up age encryption |

All subcommands have tab completions. Abbreviations expand on space (e.g. type `de` then space, it becomes `dotfiles edit`).

---

## 5. Customization cookbook

### Quick-change table

| Change | File to edit | Command |
|--------|-------------|---------|
| Homebrew packages | `dot_Brewfile.tmpl` | `dotfiles edit ~/.Brewfile` |
| Fish abbreviations/env | `config.fish.tmpl` | `dotfiles edit ~/.config/fish/config.fish` |
| Fish function | `functions/NAME.fish` | `dotfiles edit ~/.config/fish/functions/NAME.fish` |
| Starship prompt | `starship.toml` | `dotfiles edit ~/.config/starship.toml` |
| Ghostty terminal | `ghostty/config` | `dotfiles edit ~/.config/ghostty/config` |
| Ghostty theme | any time | `ghostty-theme N` |
| tmux | `tmux/tmux.conf` | `dotfiles edit ~/.config/tmux/tmux.conf` |
| VS Code settings | `code/settings.json` | `dotfiles edit ~/.config/code/settings.json` |
| VS Code extensions | `code/extensions.txt` | edit + `chezmoi apply` |
| Zed settings + MCP | `zed/settings.json.tmpl` | `dotfiles edit ~/.config/zed/settings.json` |
| Git config | `dot_gitconfig.tmpl` | `dotfiles edit ~/.gitconfig` |
| SSH hosts | `dot_ssh/config.d/*` | drop file + `chezmoi apply` |
| macOS defaults | `run_once_after_macos-defaults.sh.tmpl` | edit + `chezmoi apply` |
| Fish plugins | `.chezmoiexternal.toml` | edit + `chezmoi apply --refresh-externals` |
| Setup answers | `~/.config/chezmoi/chezmoi.toml` | `chezmoi init` |
| 1Password secrets | `.chezmoidata/secrets.toml` | `dotfiles secret add VAR op://...` |
| Claude Code security (guardrails) variant | `run_onchange_after_claude-guardrails.sh.tmpl` hash comment | edit + `chezmoi apply` |
| Personal Claude settings.json fields | `home/dot_claude/modify_settings.json` | edit + `chezmoi apply` |
| Personal Claude rules (`~/.claude/CLAUDE.md`) | `home/dot_claude/modify_CLAUDE.md.tmpl` | edit + `chezmoi apply` |
| User-authored Claude skill | `home/dot_claude/skills/NAME/` (full directory tree) | `chezmoi add ~/.claude/skills/NAME` (or surfaced automatically by `/dotfiles-sync`) |

### Walkthrough: add a new fish function

**Goal:** create a `weather` function that shows the forecast.
**File:** `home/dot_config/fish/functions/weather.fish` (new file)

```fish
dotfiles edit ~/.config/fish/functions/weather.fish
```

In the editor, write:
```fish
function weather --description "Show weather forecast"
    curl -s "wttr.in/?format=3"
end
```

Save and close. `dotfiles edit` applies (function is immediately available) and
auto-commits. Test it:

```fish
weather
```

**Expected result:** prints something like `Da Nang: ☀️ +31°C`.
The function is available in every new shell. The change is committed.

### Walkthrough: change your Starship prompt

**Goal:** shorten the directory display from 3 levels to 2.
**File:** `home/dot_config/starship.toml`

```fish
dotfiles edit ~/.config/starship.toml
```

Edit the `[directory]` section:
```toml
[directory]
truncation_length = 2
```

Save and close.

**Expected result:** your prompt immediately shows shorter paths
(e.g. `~/w/dotfiles` instead of `~/workspace/tieubao/dotfiles`).
The change is auto-committed.

### Walkthrough: add a VS Code extension

**Goal:** install the GitHub Copilot extension and persist it.
**File:** `home/dot_config/code/extensions.txt`

```fish
dotfiles edit ~/.config/code/extensions.txt
```

Add one extension ID per line (e.g. `github.copilot`). Save. Then:

```fish
chezmoi apply   # triggers the VS Code extension sync script
```

**Expected result:** VS Code installs the extension. The extensions
list is committed, so your next machine gets it too.

### Walkthrough: switch Ghostty theme

**Goal:** preview and switch terminal themes.
No file editing needed  - use the built-in helper:

```fish
ghostty-theme        # lists available themes with numbers
ghostty-theme 5      # switch to theme #5
```

**Expected result:** the terminal theme changes immediately (live
reload, no restart). The config file is updated in place.

### Walkthrough: add an SSH host

**Goal:** add a `staging` SSH host for quick access.
**File:** `home/dot_ssh/config.d/work-servers`

```fish
dotfiles edit ~/.ssh/config.d/work-servers
```

Write:
```
Host staging
    HostName 10.0.1.50
    User deploy
    IdentityFile ~/.ssh/id_ed25519
```

Save and close.

**Expected result:** `ssh staging` connects to 10.0.1.50. The main
`~/.ssh/config` includes everything in `config.d/` via `Include config.d/*`.
The change is auto-committed.

> **Don't commit infra fingerprints.** This repo is public. SSH fragments
> that contain internal Tailscale hostnames, public VPS IPs, non-standard
> ports, or purpose-revealing key names belong in `~/.ssh/config.d/*.local`
> (machine-only, gitignored) with the contents backed up to a 1Password
> Secure Note. See the next walkthrough for the restore flow.

### Walkthrough: restore private SSH host fragments

**Goal:** on a fresh machine, restore SSH fragments that aren't in this repo
because they fingerprint infrastructure (Tailscale hostnames, VPS IPs, etc.).

**Backing store:** 1Password Secure Notes, one per fragment. Each note's
`notesPlain` field holds the literal SSH config block.

**Restore on a fresh machine:**

```fish
# Mac mini (personal infra, Private vault)
op read "op://Private/SSH config: mini/notesPlain" \
  > ~/.ssh/config.d/mini.local

# Trading VPS (Trading vault)
op read "op://Toolkit/SSH config: trading-egress-tokyo/notesPlain" \
  > ~/.ssh/config.d/trading-egress-tokyo.local

chmod 600 ~/.ssh/config.d/*.local
```

**Verify:** `ssh -G mini` (or whichever host) prints the resolved config.
The main `~/.ssh/config` already does `Include config.d/*`, so untracked
fragments dropped into that directory are picked up automatically.

**Adding a new private fragment:**

1. Edit `~/.ssh/config.d/<host>.local` directly with `chmod 600` afterward.
2. Create a Secure Note in 1Password with title `SSH config: <host>` and
   paste the contents into the notes field.
3. The `*.local` suffix is gitignored repo-wide; nothing else to do.

**Why this isn't `chezmoi`-templated:** the file is tiny, rarely changes,
and `chezmoi apply` should stay popup-free. A Secure Note + a one-line
`op read` on bootstrap is simpler than threading `onepasswordRead` through
templates that fire a biometric on every apply.

### Walkthrough: back up your SSH keys

**Goal:** make sure no SSH private key exists on only one machine, and keep
an offline escape hatch in case 1Password is ever unavailable.

**Tools:** `dotfiles ssh audit`, `dotfiles ssh adopt`, `dotfiles ssh backup`.
Requires `op` signed in. Backup additionally requires `age` and
`~/.config/chezmoi/key.txt`.

**Step 1. See what you have.**

```fish
dotfiles ssh audit
```

The output shows four sections: on-disk keys, agent keys, 1P SSH items, and
a backup-status summary. Any `⚠ adopt` or `⚠ plaintext` flag means the key
is on disk only. A `⚠ weak` or `⚠ old` flag is a rotation hint, not a
backup concern.

**Step 2. Adopt each disk key into 1Password (guided).**

```fish
dotfiles ssh adopt ~/.ssh/id_ed25519_trading_vps
```

The command is a guided manual flow: 1Password CLI cannot import existing
SSH private keys, so the tool opens the 1P desktop app, copies the key to
your clipboard, waits for you to create a new SSH Key item and paste, then
verifies the import by fingerprint and clears the clipboard. The on-disk
file is never touched. After verification, the 1P SSH agent serves the key
automatically.

**Step 3. Investigate unknown-usage keys before retiring.**

A disk key you no longer remember using is not safe to delete. Before
removing the disk copy, confirm it is unused:

```fish
# Which hosts trust this public key?
for host in $KNOWN_HOSTS_YOU_CAN_REACH
    ssh $host "grep -l '$(cat ~/.ssh/id_rsa.pub | awk '{print $2}')' ~/.ssh/authorized_keys 2>/dev/null"
end

# Which key does an existing SSH session offer?
ssh -v $host 2>&1 | grep -i 'offering\|identity file'

# Check remote SSH key lists (browser)
#   GitHub    https://github.com/settings/keys
#   GitLab    https://gitlab.com/-/user_settings/ssh_keys
#   Bitbucket https://bitbucket.org/account/settings/ssh-keys/
#   VPS vendor / cloud provider panels
```

After adoption, keep the disk copy for 3 months and re-run `dotfiles ssh
audit` monthly. If nothing surfaces, move the file to `~/.Trash/` and
re-audit.

**Step 4. Write an offline escape hatch (quarterly).**

Plug in a USB drive, then:

```fish
dotfiles ssh backup --destination /Volumes/Backup
```

Produces `/Volumes/Backup/ssh-keys-YYYY-MM-DD.age`, encrypted to the same
age recipient used for `chezmoi`-encrypted files. Label the drive and store
it somewhere you can physically reach if 1Password is lost.

**Step 5. Restore drill (do this once so you know it works).**

On any machine with your age key available:

```fish
age --decrypt -i ~/.config/chezmoi/key.txt /Volumes/Backup/ssh-keys-YYYY-MM-DD.age
```

Output is the plaintext bundle. Confirm it contains `=== BEGIN KEY` blocks
for every key you expect. Then close the terminal without saving the
output to disk. To actually re-import a key on a new machine, paste the
private-key block into a new 1P SSH Key item in the desktop app; op CLI
cannot import SSH keys, so this step is manual.

### Walkthrough: upgrade claude-guardrails

**Goal:** pick up a new `claude-guardrails` release (e.g. v0.3.7 -> v0.3.8).
**File:** `home/.chezmoiscripts/run_onchange_after_claude-guardrails.sh.tmpl`

The pin is a git tag from the claude-guardrails GitHub repo (not an npm
version — the project does not publish every release to npm). Upgrades
are deliberate. Edit two lines:

```bash
# guardrails: variant={{ .guardrails_variant }} ref=v0.3.8
...
REF="v0.3.8"
```

The tag must already exist upstream at `github.com/dwarvesf/claude-guardrails`.
Commit and run `chezmoi apply`. The `run_onchange_` hash changes, the script
fires, and `npx -y github:dwarvesf/claude-guardrails#v0.3.8 install <variant>`
merges the new version into `~/.claude/settings.json`. Your personal overlay
(`modify_settings.json`) is unaffected.

**Expected result:** `jq '."$schema", (.permissions.deny | length), (.hooks.PreToolUse | length)' ~/.claude/settings.json`
shows the current schemastore URL, 21 deny rules (lite) or 40 (full),
and the expected hook count for the variant.

### Walkthrough: change the guardrails variant (or disable it)

**Goal:** switch from `lite` to `full`, or opt a headless box out entirely.
**File:** `~/.config/chezmoi/chezmoi.toml`

```toml
[data]
  guardrails_variant = "full"   # or "lite" or "none"
```

Run `chezmoi apply`. On `none`, the install script exits early and no
guardrails are written; existing security fields in `~/.claude/settings.json`
will stay until you remove them by hand (uninstall is not automatic, by
design - silent removal of security is a bigger risk than leftover state).

### Walkthrough: back up a Claude skill

**Goal:** make a hand-written skill at `~/.claude/skills/my-skill/` survive a
fresh-machine bootstrap and reach your other Macs.
**File:** `home/dot_claude/skills/my-skill/` (whole directory tree)

Two paths work, pick whichever fits the moment.

**Easy path (next sync):** do nothing. The next time you run
`/dotfiles-sync`, the skill is surfaced under "New Claude skills" with the
standard prompt:

```
[Core]  versioned in repo, deployed to every machine
[Local] this machine only (recorded in ~/.config/dotfiles/skills.local)
[Skip]  decide later, resurfaces next sync
```

Choose **core** for skills you want everywhere; **local** for experimental
or machine-specific ones.

**Manual path (right now):**

```fish
chezmoi add ~/.claude/skills/my-skill   # whole directory: SKILL.md + any references/ + templates/
chezmoi diff                            # review what got added
git -C $(chezmoi source-path) add home/dot_claude/skills/my-skill
git -C $(chezmoi source-path) commit -m "feat(claude): track my-skill under chezmoi"
```

**Expected result:** the skill is present at
`home/dot_claude/skills/my-skill/` in the repo, and `chezmoi apply` on any
other machine deploys it to `~/.claude/skills/my-skill/`. Plugin-installed
skills live under `~/.claude/plugins/` (not `~/.claude/skills/`) and are
filtered out of the drift scan, so the marketplace remains the source of
truth for those.

To stop tracking a skill that turned out to be machine-specific:

```fish
chezmoi forget ~/.claude/skills/my-skill
mkdir -p ~/.config/dotfiles && echo my-skill >> ~/.config/dotfiles/skills.local
```

(`dotfiles local promote/demote` does not yet support skills the way it
does brew, cask, and ext. Filed as a follow-up if the manual flow proves
too clunky in practice.)

### Walkthrough: add a personal Claude Code setting

**Goal:** add a new field to `~/.claude/settings.json` that should exist on
every machine without going into claude-guardrails.
**File:** `home/dot_claude/modify_settings.json`

The file is a bash+jq script that runs on every `chezmoi apply`. It reads
the live file on stdin and emits a patched version. To add a field, extend
the first jq merge object:

```jq
$existing + {
    yourNewField: ($existing.yourNewField // "default value"),
    ...
}
```

The `//` operator keeps any existing value on the machine, only falling
back to the default. For hooks, follow the Stop-hook pattern already in
the script (filter by marker string + append) so repeated applies stay
idempotent.

**Do not** re-create `home/dot_claude/settings.json` as a regular file.
That path was abandoned in S-36 because it races with the guardrails
installer - see `docs/specs/S-36-guardrails-as-managed-installer.md`.

### Walkthrough: change your personal Claude Code rules

**Goal:** add a new Tech stack preference, Security Rule, or behavioral
guideline to `~/.claude/CLAUDE.md` so it applies to every Claude Code session
on every machine.
**File:** `home/dot_claude/modify_CLAUDE.md.tmpl`

The file at `~/.claude/CLAUDE.md` has two regions separated by the marker
`# --- END claude-context ---`:

| Region | Owner | Sync behavior |
|--------|-------|---------------|
| **Above** the marker | Your personal context generator (auto-regenerated on this machine) | Machine-local; not in the repo |
| **Below** the marker | `home/dot_claude/modify_CLAUDE.md.tmpl` (a chezmoi `modify_` script) | Same on every machine; committed |

The `modify_` script is templated with chezmoi data. It reads `.email` and the
optional `.work_email_domains` prompt (set during `chezmoi init`) and feeds
them into the ownership-check line inside the rules, so the email list isn't
hardcoded.

**Do not hand-edit `~/.claude/CLAUDE.md` below the marker.** The modify
script re-asserts the canonical content on every `chezmoi apply` — any
manual edit to the deployed file is silently overwritten.

**Recommended: ask Claude.** Open any Claude Code session and describe the
change in plain language:

> "Add a tech stack preference: prefer Biome over Prettier+ESLint."
>
> "Add a security rule: never deploy to production on a Friday."
>
> "Drop the mention of conda from the Python row — I don't care about it."

Claude edits the template in the right place, runs `chezmoi apply`, verifies
the rendered file matches, and offers a commit.

**Manual alternative:**

```fish
chezmoi edit ~/.claude/CLAUDE.md     # opens modify_CLAUDE.md.tmpl (the source)
# edit the content inside the <<'MARKDOWN' ... MARKDOWN heredoc
chezmoi apply ~/.claude/CLAUDE.md    # re-runs the modify script
dotfiles cd
git add home/dot_claude/modify_CLAUDE.md.tmpl
git commit -m "chore(claude): <what changed>"
git push
```

**Detection.** `chezmoi diff ~/.claude/CLAUDE.md` is empty when the rendered
file matches the template. Non-empty output means either the template
changed (commit it) or someone hand-edited the deployed file (port the edit
up into the template, then apply to re-sync).

**Expected result:** the next Claude Code session on this Mac picks up the
change immediately. Other machines get it after `git pull && chezmoi apply`.

---

## 6. Secrets management

### The three tiers

| Tier | When to use | Command |
|------|------------|---------|
| **Auto-loaded** | Env var in every shell session | `dotfiles secret add VAR "op://..."` |
| **Runtime** | Occasional CLI use, don't pollute every env | `op-env VAR "op://..."` |
| **One-off** | Quick inline use | `set -x VAR (op read "op://...")` |

### Adding a new secret

```fish
dotfiles secret add OPENAI_API_KEY "op://Private/OpenAI/credential"
```

<p align="center">
  <img src="dotfiles_workflow_secrets.svg" alt="Secrets workflow" width="680">
</p>

This command:
1. Creates the 1Password item if it doesn't exist (prompts for the value)
2. Registers the `op://` binding in `secrets.toml`
3. Runs `chezmoi apply` to update `secrets.fish` with the lazy-resolve call (no 1P call during apply)
4. Auto-commits the registry change (only the `op://` ref, never the value)

Open a new shell (or `exec fish`) to pick up the variable. The first shell on this machine triggers one 1Password prompt per newly registered secret; Keychain caches the value silently for every shell after.

### Rotating a token

Update the value in 1Password (app or CLI). Then:

```fish
dotfiles secret refresh OPENAI_API_KEY   # clears Keychain cache, re-fetches from 1P
exec fish
```

No repo change needed -- the `op://` reference hasn't changed.

### Removing a secret

```fish
dotfiles secret rm OPENAI_API_KEY    # unregisters from secrets.toml, auto-commits
```

### Listing current secrets

```fish
dotfiles secret list
# Registered secrets (cache status from macOS Keychain):
#   [cached] OPENAI_API_KEY → op://Private/OpenAI/credential
#   [ empty] NEW_TOKEN → op://Private/New/credential
```

### How it works under the hood

`secrets.toml` is a chezmoi data file loaded as `.secrets` in templates.
`secrets.fish.tmpl` iterates the registry and emits one `set -gx` per entry,
but **does not resolve** via `onepasswordRead`. Instead, each emitted line
calls `~/.local/bin/secret-cache-read VAR OP_REF` at shell startup time,
which:

1. Looks up `VAR` in macOS Keychain (silent, ~1 ms)
2. On cache miss, runs `op read OP_REF` (1P popup if interactive)
3. Stores the result back in Keychain for next time

This means **`chezmoi apply` never calls 1Password**. Secrets are only
fetched when a shell actually starts for the first time on a machine, or
after `dotfiles secret refresh`. The rendered `secrets.fish` on disk is
safe to grep -- it contains only references, not values.

### Service account for agent subprocess `op read` (S-49)

Claude Code (and other agents) sometimes needs to call `op read op://...`
as a subprocess mid-session, for secrets we haven't pre-registered. Those
calls hit a wall: `op` refuses to trigger biometric when stdin is not a
TTY, so the read fails silently.

The fix is a **dual-mode** setup. `OP_SERVICE_ACCOUNT_TOKEN` is auto-loaded
into every fish shell so subprocesses inherit bearer auth (headless `op read`
works). Inside interactive fish, a small function intercepts `op` and strips
the token inline so daily commands fall back to biometric and see all your
vaults.

```
fish login → set -gx OP_SERVICE_ACCOUNT_TOKEN ...
   │
   ├─ Interactive `op vault list` typed at prompt
   │     → fish function `op` runs, status is-interactive = true
   │     → env -u OP_SERVICE_ACCOUNT_TOKEN command op vault list
   │     → biometric, all vaults visible
   │
   └─ Subprocess (zsh, bash, scripts, claude)
         → no fish function in scope
         → calls `op` binary directly
         → bearer auth via env → SA-scoped, headless
```

Requires a 1Password **Business or Teams** plan. Family/Individual plans
cannot create service accounts; stick with per-secret registration.

**One-time setup per user:**

1. In the 1Password web admin, create a service account scoped to the
   vaults the agent should see. Recommended: a dedicated `Agents` vault,
   not `Private`, so a token leak doesn't expose personal secrets.
2. Store the resulting `ops_...` token as a regular 1Password item,
   e.g. `op://Private/op-service-account-<purpose>/credential`.
3. Register on each machine:
   ```fish
   dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN \
       "op://Private/op-service-account-<purpose>/credential"
   exec fish
   ```

**Verifying it works:**

```fish
echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 4   # ops_  (auto-loaded)

# Interactive op = biometric, all vaults
op whoami | grep "User Type:"                # USER_OF_ACCOUNT
op vault list                                 # all your vaults

# Subprocess op = bearer auth, SA scope, headless
bash -c 'op whoami | grep "User Type:"'       # SERVICE_ACCOUNT
bash -c 'op vault list'                       # only SA-scoped vaults

# `with-agent-token` still works as a debug escape hatch.
with-agent-token op whoami                    # SERVICE_ACCOUNT (forced)
```

**Rotating the token:** revoke in the 1P web console, generate a new one,
update the 1P item, then on each machine:

```fish
dotfiles secret refresh OP_SERVICE_ACCOUNT_TOKEN
exec fish
```

**Bypassing the interceptor on demand:**

If you need to test the SA scope from inside fish (e.g., "what does the
agent see?"), use either:

```fish
command op vault list      # skip the function definition
with-agent-token op vault list   # explicit per-invocation wrapper
```

Both should return the SA-scoped subset, not your full vault list.

**Full workflow + analysis:** [`docs/1password.md`](1password.md) -- mental model, vault tiering, troubleshooting, spec chain.

Spec history: [`docs/specs/S-49`](specs/S-49-dual-mode-op-via-fish-interceptor.md) (current),
[`docs/specs/S-47`](specs/S-47-agent-token-opt-in-wrapper.md) (amended),
[`docs/specs/S-42`](specs/S-42-service-account-agent-auth.md) (superseded).

### Why Keychain instead of a dotfile cache

- **Silent after approval.** macOS prompts once per app ("allow access to this keychain item?"); after "Always Allow", reads are invisible
- **Encrypted at rest** by the OS
- **Machine-local**, which matches the rest of the local-override philosophy
- **Easy to invalidate** per-entry via `security delete-generic-password` (wrapped as `dotfiles secret refresh`)

---

## 7. Multi-machine setup

### Deploying to a second Mac

On the new machine:

```bash
git clone https://github.com/dwarvesf/dotfiles ~/dotfiles
cd ~/dotfiles && ./install.sh
```

The setup wizard prompts for the same config (name, email, editor,
1Password). If you use 1Password, sign in first (`eval $(op signin)`),
and all secrets are pulled automatically.

### Headless/server mode

During `chezmoi init`, answer `headless = true`. This skips:
- GUI apps (Ghostty, VS Code, Zed)
- Mac App Store apps
- Dev casks (Docker, Figma, etc.)
- macOS defaults

You get: Fish shell, CLI tools, git config, SSH config, tmux.

### Keeping machines in sync

On any machine:

```fish
dotfiles update    # git pull + chezmoi apply
```

Or manually:

```fish
cd ~/dotfiles && git pull
chezmoi apply
```

### Machine-specific overrides

chezmoi templates handle per-machine differences. The `.chezmoi` variable
provides hostname, OS, and arch. Example in a `.tmpl` file:

```
{{ if eq .chezmoi.hostname "work-mbp" }}
# work-specific config here
{{ end }}
```

The `headless` flag is the most common override  - it gates entire
sections of the Brewfile and script execution.

---

## 8. Troubleshooting

Start with `dotfiles doctor`  - it catches most issues.

### "I edited the wrong file"

You edited `~/.config/fish/config.fish` directly instead of the source.
Your change works now but will be lost on the next `chezmoi apply`.

**Fix:** run `dotfiles drift` to detect the drift and re-absorb it into the source.

### "chezmoi apply wants to overwrite my change"

Same root cause: the deployed file differs from the source. Options:

1. `dotfiles drift`  - pull the deployed version back into source
2. `chezmoi merge <path>`  - three-way merge
3. `chezmoi apply --force`  - overwrite deployed with source (destructive)

### "1Password errors"

- **"not signed in"**: run `eval (op signin)` or `eval $(op signin)` in bash
- **"item not found"**: check vault name and item title match the `op://` path
- **"connect timeout"**: 1Password CLI needs internet for the first auth

### "Template rendering failed"

A `.tmpl` file is missing a variable. Usually means `chezmoi init` needs
to be re-run:

```fish
chezmoi init
chezmoi apply
```

### "Brewfile didn't re-run"

The brew script only fires when the Brewfile content changes (chezmoi
tracks a hash). Force it:

```fish
brew bundle --file=~/.Brewfile
```

### "Fish function not found"

The function file must be named exactly `FUNCTIONNAME.fish` in
`~/.config/fish/functions/`. Check:

```fish
functions --names | grep yourfunction
ls ~/.config/fish/functions/yourfunction.fish
```

### "Shell startup is slow"

Benchmark it:

```fish
dotfiles bench
```

Common causes: 1Password CLI calls on every shell (move to auto-loaded
secrets), too many PATH additions, slow network for async prompt.

### "Claude Code blocked my prompt" (guardrails false positive)

The `claude-guardrails` prompt scanner saw something that matched a
secret pattern. The stderr message shows which pattern hit.

Most common causes and fixes:

| Pattern | Likely trigger | Fix |
|---------|---------------|-----|
| `BIP39 mnemonic` | 12+ consecutive words all in the BIP39 wordlist (rare in prose, near-zero FP rate after 0.3.7) | Rephrase. Check `~/.claude/hooks/patterns/bip39-english.txt`. |
| `Secret-like variable assignment` | A sentence containing `api_key = something-16-chars-plus` or similar | Rephrase without the literal pattern. |
| `Hex private key (64 chars)` | Git commit SHA pasted (sha256 is 64 hex chars) | Rephrase; git short SHAs (7-10 chars) are safe. |

If a real credential triggered the block: it was **not** sent to the
model, but you should still rotate it on the upstream service because
the prompt may already be in your shell history / clipboard / editor
undo buffer. The pattern files at `~/.claude/hooks/patterns/` are
installed by claude-guardrails; do not hand-edit them (they will be
overwritten on next upgrade). File an issue upstream if a pattern
consistently false-positives.

### "Claude Code has no security hooks / `$schema` warning"

Guardrails isn't active on this machine. Check in order:

1. `jq '."$schema"' ~/.claude/settings.json` - must be
   `https://json.schemastore.org/claude-code-settings.json`. Any other
   value (especially `https://claude.ai/schemas/...`) means Claude Code
   silently discards the file.
2. `jq '.guardrails_variant' ~/.config/chezmoi/chezmoi.toml` (should be
   `"lite"`, `"full"`, or `"none"`). If missing, re-run `chezmoi init`.
3. Re-run `chezmoi apply` - the `run_onchange_after_claude-guardrails.sh`
   script should fire. If it doesn't, check `~/.cache/dotfiles-apply.log`
   for errors.
4. Fallback: `npx -y claude-guardrails@latest install lite` directly.

### Nuclear options

If something is deeply broken:

```fish
# Re-run setup wizard (re-prompts for all config)
chezmoi init

# Force apply everything (overwrites all deployed files)
chezmoi apply --force

# Full reinstall (teardown + rebuild)
cd ~/dotfiles && ./install.sh --force
```

---

## 9. Lifecycle: install, update, uninstall

### Install (first time)

```bash
git clone https://github.com/dwarvesf/dotfiles ~/dotfiles
cd ~/dotfiles && ./install.sh
```

This installs Homebrew, chezmoi, runs the setup wizard, deploys all
configs (including `~/.claude/commands/dotfiles-sync.md`), installs
packages, sets Fish as default shell, and prints a summary.

After install, `/dotfiles-sync` is available in Claude Code from any
directory. See [section 1](#1-the-llm-workflow).

### Update (ongoing)

**Primary (LLM-assisted):** run `/dotfiles-sync` in Claude Code. Claude
detects drift, you approve, it syncs.

**Pull from remote** (new commits from another machine):

```fish
dotfiles update    # git pull + chezmoi apply
```

**Re-run setup wizard** (change name, email, editor, 1Password config):

```fish
chezmoi init       # re-prompts for all answers
chezmoi apply      # deploy with new answers
```

**Reinstall from scratch** (teardown + rebuild):

```bash
cd ~/dotfiles && ./install.sh --force
```

This removes chezmoi state and config, re-links, re-runs the wizard,
and re-applies everything.

### Uninstall

There is no automated uninstall. To remove this dotfiles setup:

**1. Restore default shell** (if you're also removing Fish):

```bash
chsh -s /bin/zsh
```

Skip this if you want to keep Fish as your shell.

**2. Remove deployed configs:**

```bash
# See what chezmoi manages
chezmoi managed

# Remove all chezmoi-managed files from $HOME
chezmoi managed | while read f; do rm -f "$HOME/$f"; done

# Remove chezmoi state and config
rm -rf ~/.local/share/chezmoi
rm -rf ~/.config/chezmoi
```

**3. Remove the Claude Code slash command:**

```bash
rm -rf ~/.claude/commands/dotfiles-sync.md
```

**4. Remove the repo:**

```bash
rm -rf ~/dotfiles
```

**5. Optionally uninstall Homebrew packages:**

```bash
# See what was installed via the Brewfile
brew bundle list --file=~/.Brewfile

# Remove everything in the Brewfile
brew bundle cleanup --force --file=~/.Brewfile

# Or uninstall Homebrew entirely
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
```

After uninstall, your Mac reverts to Zsh with default configs. Any
1Password secrets remain in your vault (unchanged).

---

## 10. Architecture reference

<p align="center">
  <img src="dotfiles_architecture.svg" alt="Architecture overview" width="680">
</p>

### Script execution order

During `chezmoi apply`, scripts run in this order:

1. `run_before_aa-init.sh`  - resets the apply log
2. `run_before_ab-1password-check.sh`  - validates 1Password CLI
3. `run_onchange_before_brew-bundle.sh`  - `brew bundle` (triggers on Brewfile change)
4. **File deployment**  - templates rendered, files copied
5. `run_once_after_*`  - one-time setup (Fish shell, macOS defaults, MAS apps, toolchains)
6. `run_onchange_after_*`  - VS Code extensions, Zed config (triggers on content change)
7. `run_after_zz-summary.sh`  - styled apply summary with OK/warning/error counts

`run_once_` scripts won't re-run unless their content changes.
`run_onchange_` scripts re-run when the template output changes.

### How templates work

Any file ending in `.tmpl` is rendered through Go's `text/template`
engine at apply time. chezmoi provides variables from:

- `chezmoi init` answers (`.name`, `.email`, `.editor`, `.headless`, `.use_1password`)
- `.chezmoidata/*.toml` files (`.secrets` from `secrets.toml`)
- Built-in `.chezmoi.*` (hostname, OS, arch, username)

Every `.tmpl` file validates required variables at the top with
`hasKey`/`fail` guards. Missing variables produce actionable error
messages instead of cryptic Go template errors.

### External downloads

Fish plugins and completions are defined in `.chezmoiexternal.toml` as
GitHub URLs. chezmoi downloads and caches them with a 30-day refresh.
Force re-download with `dotfiles refresh` or `chezmoi apply --refresh-externals`.

### Design decisions

Architectural choices are documented as ADRs in `docs/decisions/`:

- [001: chezmoi over GNU Stow](decisions/001-chezmoi-over-stow.md)
- [002: Fish over Zsh](decisions/002-fish-over-zsh.md)
- [003: Ghostty over Kitty](decisions/003-ghostty-over-kitty.md)
- [004: 1Password for secrets](decisions/004-1password-for-secrets.md)
- [005: No plugin manager for Fish](decisions/005-no-plugin-manager-for-fish.md)
- [006: Auto-commit workflow](decisions/006-auto-commit-workflow.md)

---

## Appendix: cheat sheet

### Commands at a glance

| I want to... | Command | Abbreviation |
|--------------|---------|-------------|
| **Batch sync everything** | **`/dotfiles-sync` (in Claude Code)** | |
| Edit any config | `dotfiles edit <path>` | `de` |
| Detect and fix drift | `dotfiles drift` | `dd` |
| Apply all changes | `dotfiles sync` | `ds` |
| Pull latest + apply | `dotfiles update` | `dfu` |
| See what would change | `dotfiles diff` | |
| Check health | `dotfiles doctor` | |
| Add a Homebrew package | `dotfiles edit ~/.Brewfile` | |
| Add a secret | `dotfiles secret add VAR "op://..."` | |
| List secrets | `dotfiles secret list` | |
| Remove a secret | `dotfiles secret rm VAR` | |
| Rotate a secret | Update in 1Password, then `chezmoi apply` | |
| Add a fish function | `dotfiles edit ~/.config/fish/functions/NAME.fish` | |
| Switch Ghostty theme | `ghostty-theme N` | |
| Benchmark startup | `dotfiles bench` | |
| Backup config | `dotfiles backup` | |
| Re-run setup wizard | `chezmoi init` | |

### Key file locations

| What | Source (repo) | Target (machine) |
|------|--------------|-------------------|
| Fish config | `home/dot_config/fish/config.fish.tmpl` | `~/.config/fish/config.fish` |
| Fish functions | `home/dot_config/fish/functions/` | `~/.config/fish/functions/` |
| Ghostty | `home/dot_config/ghostty/config` | `~/.config/ghostty/config` |
| Starship | `home/dot_config/starship.toml` | `~/.config/starship.toml` |
| tmux | `home/dot_config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` |
| Git | `home/dot_gitconfig.tmpl` | `~/.gitconfig` |
| Brewfile | `home/dot_Brewfile.tmpl` | `~/.Brewfile` |
| Secrets registry | `home/.chezmoidata/secrets.toml` | (data file, not deployed) |
| Rendered secrets | `home/dot_config/fish/conf.d/secrets.fish.tmpl` | `~/.config/fish/conf.d/secrets.fish` |
