# dotfiles

![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-000?logo=apple&logoColor=white)
![Fish](https://img.shields.io/badge/Fish-Shell-4AAE46?logo=gnubash&logoColor=white)
![Starship](https://img.shields.io/badge/Starship-Prompt-DD0B78?logo=starship&logoColor=white)
![Ghostty](https://img.shields.io/badge/Ghostty-Terminal-1a1a2e)
![chezmoi](https://img.shields.io/badge/chezmoi-Managed-blue)
![1Password](https://img.shields.io/badge/1Password-Secrets-0572EC?logo=1password&logoColor=white)
![CI](https://img.shields.io/github/actions/workflow/status/dwarvesf/dotfiles/test.yml?label=CI&logo=github)

**Multi-machine dotfiles maintained by an LLM.** You operate each Mac freely; Claude detects what drifted, asks whether new packages are shared across machines or specific to this one, and keeps everything in sync. **You don't need to sync this repo by hand** — there's a `dotfiles` CLI for offline edits, but day-to-day you just talk to Claude.

## The idea

Most dotfiles repos expect you to edit the source, apply, commit, push. In practice, nobody does this consistently. You `brew install` while debugging, tweak a config directly, add an API key, and move on. After a few weeks, the repo is stale. Add a second machine to the mix and the workflow becomes intractable -- machine-specific tools end up in the shared template and propagate everywhere.

This repo works differently. You change things on each machine independently. Periodically, you ask Claude to catch up:

```
You:    /dotfiles-sync
Claude: [scans machine  - packages, configs, extensions, secrets]

Claude: Dotfiles sync report (@ work-mac)
          Config drift: Zed settings (2 new MCP servers)
          New packages: ollama, chrysalis, lunar, rclone
          Stale: raycast, slack (not installed)

        Classify the new ones?
          [Core] shared across all machines
          [Local] this machine only

You:    chrysalis and lunar are local (hardware-specific),
        ollama and rclone are core. drop raycast and slack.

Claude: [adds ollama+rclone to Brewfile (committed), appends
         chrysalis+lunar to ~/.Brewfile.local (NOT committed),
         re-adds Zed settings, drops stale entries, logs to
         sync-log.md tagged @ work-mac, commits]
        Done. 1 commit. Push?

You:    push
```

Two sentences from you. The LLM handled the classification, kept machine-specific tools out of the shared repo, and tagged the sync log so the next machine knows what happened where.

The pattern is general and works with any dotfiles manager and any LLM agent. The full write-up, including setup instructions, is in **[docs/llm-dotfiles.md](docs/llm-dotfiles.md)**.

## How it works

<p align="center">
  <img src="docs/dotfiles_llm_sync_workflow.svg" alt="LLM sync workflow: machine drifts, Claude syncs" width="680">
</p>

[chezmoi](https://www.chezmoi.io/) is the backbone. It separates the source (repo) from the target ($HOME), renders templates with injected secrets, and provides drift detection via `chezmoi status`. This two-layer model is what makes LLM-maintained sync possible: the LLM can safely scan, diff, and re-add without touching secrets in git.

The `/dotfiles-sync` command is installed to `~/.claude/commands/` during setup, so it's available in Claude Code from any directory. The command prompt (at [.claude/commands/dotfiles-sync.md](.claude/commands/dotfiles-sync.md)) teaches Claude what to scan:

| Dimension | What it detects |
|-----------|----------------|
| Config drift | Files changed on machine but not in repo |
| Brew packages | Installed but not in Brewfile or `~/.Brewfile.local` |
| Cask apps | GUI apps installed but not tracked (core or local) |
| VS Code extensions | New / removed extensions (core list + per-machine list) |
| Fish functions | Functions created outside chezmoi |
| SSH configs | New host configs in `config.d/` |
| Claude skills | User-authored skills in `~/.claude/skills/` not yet tracked (plugin-installed skills filtered out) |
| Secrets | Hardcoded keys that should be in 1Password |

Every sync is logged in [docs/sync-log.md](docs/sync-log.md) tagged with the machine hostname (`@ work-mac`, `@ personal-mini`), so future syncs on any machine have full cross-machine context.

## Multi-machine sync

The repo is designed for running across N Macs simultaneously. Two patterns make this work without manual coordination:

**`.local` overrides for per-machine state.** Anything machine-specific lives outside the shared template -- `~/.Brewfile.local` for hardware-specific brew/casks, `~/.config/code/extensions.local.txt` for editor extensions, plus `config.local.fish`, `tmux.local.conf`, and `.gitconfig.local` for shell/editor configs. These files are gitignored AND in `.chezmoiignore`, so they can never accidentally sync to other machines. Items move between core and local with one command:

```fish
dotfiles local promote cask raycast       # local → core (shared with all machines)
dotfiles local demote brew sentencepiece  # core → local (this machine only)
```

**Lazy 1Password secrets via Keychain cache.** The shared template never bakes secrets in -- it bakes in a *call* to a Keychain-first reader. `chezmoi apply` triggers zero 1Password popups; the first shell on a fresh machine triggers exactly one popup per registered secret (then cached silently in macOS Keychain). 1Password remains the source of truth across machines; Keychain is just the per-machine cache.

To bring up an additional Mac, follow the [Quick start](#quick-start) below — the same bootstrap runs on every machine, and the `/dotfiles-sync` prompt in the cheat sheet is what classifies whatever is unique to the new one. The full multi-machine test plan is in [docs/testing.md](docs/testing.md).

## Quick start

```bash
git clone https://github.com/dwarvesf/dotfiles ~/dotfiles
cd ~/dotfiles && ./install.sh
```

A [gum](https://github.com/charmbracelet/gum)-powered wizard prompts for your name, email, editor, headless mode, and 1Password. First run takes ~30 minutes (Homebrew downloads). The Brewfile includes Claude Code itself, so once the installer finishes you have everything needed to talk to Claude about this repo.

**Requirements:** macOS 12+, Apple Silicon (Intel works too).

### Day-to-day: tell Claude what you want

After install, you never edit this repo by hand. Open Claude Code anywhere and say things like:

| What you want | What to say |
|---|---|
| Catch up after drift | `/dotfiles-sync` |
| Add a shared tool | *"Add ripgrep to dotfiles, shared across machines"* |
| Add a tool just for this Mac | *"Install chrysalis but local to this Mac"* |
| Promote local → core | *"Promote raycast from local to core"* |
| Demote core → local | *"Move sentencepiece to local only"* |
| Register a 1Password secret | *"Register OPENAI\_API\_KEY from op://Private/OpenAI/credential"* |
| Rotate a cached secret | *"Refresh my GITHUB\_TOKEN in Keychain"* |
| Remove a package | *"Drop slack from dotfiles"* |
| Health check | *"Run `dotfiles doctor` and explain any issues"* |

Claude maps each request to the right `dotfiles` subcommand, template edit, or git action, then commits with a descriptive message. The full conversation-driven workflow is in [docs/guide.md](docs/guide.md).

<details>
<summary><b>Other install methods</b></summary>

**Existing Mac** (configs only, skip brew/mas/defaults):
```bash
cd ~/dotfiles && ./install.sh --config-only
```

**Without git** (fresh Mac, no Xcode CLT):
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply dwarvesf
```

**Flags:** `--check` (dry-run), `--force` (reinit from scratch)

</details>

## The stack

| Layer | Tools |
|-------|-------|
| **Shell** | Fish + Starship prompt + plugins (autopair, done, sponge, async-prompt) |
| **Terminal** | Ghostty (GPU-rendered, catppuccin-mocha, JetBrains Mono) |
| **Multiplexer** | tmux (C-a prefix, vim nav, fzf session picker) |
| **Editors** | VS Code + Zed (settings, extensions, MCP servers with 1P secrets) |
| **Git** | delta diffs, aliases, commit template |
| **SSH** | 1Password SSH Agent, modular config.d/ |
| **Secrets** | 1Password `op://` templates + data-driven registry |
| **Packages** | Layered Brewfile (base/dev/apps) + Mac App Store |
| **Languages** | mise (Node, Python, Go, Ruby) |
| **macOS** | 30+ `defaults write` (Dock, Finder, keyboard, screenshots) |

Every tool is chosen for speed, ergonomics, and native macOS integration. No legacy defaults, no bloat.

## Offline fallback

When you're not in a Claude session (SSH, airplane, quick edit), the `dotfiles` CLI works standalone:

```fish
dotfiles edit ~/.config/fish/config.fish   # edit + apply + auto-commit
dotfiles drift                              # detect and re-absorb drift
dotfiles local list                         # show machine-specific overrides
dotfiles local promote cask <name>          # move from local to core
dotfiles secret list                        # show secrets + Keychain cache status
dotfiles secret refresh <VAR>               # invalidate cache, re-fetch from 1P
dotfiles ssh audit                          # inventory disk/agent/1P keys + backup status
dotfiles ssh adopt ~/.ssh/<name>            # import disk key to 1P (disk copy untouched)
dotfiles ssh backup --destination /path     # age-encrypted bundle for offline escape hatch
dotfiles doctor                             # health check (incl. .local pattern integrity)
```

Full command reference, walkthroughs, secrets management, multi-machine setup, and troubleshooting are in the **[user guide](docs/guide.md)**.

## Lifecycle

| Stage | Command |
|-------|---------|
| **Install** | `git clone ... ~/dotfiles && cd ~/dotfiles && ./install.sh` |
| **Update** (LLM) | `/dotfiles-sync` in Claude Code |
| **Update** (manual) | `dotfiles update` (pull + apply) |
| **Reinstall** | `./install.sh --force` |
| **Uninstall** | See [guide](docs/guide.md#9-lifecycle-install-update-uninstall) |

## Security

This repo is safe to make public. Actual secrets (API keys, tokens, passwords) are never committed; only `op://` references to 1Password items appear in the source. The rendered `secrets.fish` on disk doesn't even contain the real values -- it just has a lazy call to a Keychain-first reader. Real values flow: 1Password → first shell on each machine → Keychain → env var. The shared template never sees plaintext.

The `op://` references do reveal 1Password vault and item names (e.g. `op://Private/OpenAI/credential`). This is intentional: it makes the repo forkable. If you fork, replace the item names with your own. The vault structure tells someone what services you use, not how to access them.

**`.local` files are never committed.** Machine-specific Brewfile entries, VS Code extensions, fish/tmux/git overrides all live in gitignored `~/.X.local` files. `dotfiles doctor` audits git history to confirm none ever leaked.

**Agents and non-interactive `op read` (dual-mode).** Subprocesses (Claude Code's Bash tool, scripts, bash one-liners) inherit `OP_SERVICE_ACCOUNT_TOKEN` from your fish shell and use bearer auth -- no biometric prompt mid-session. Inside interactive fish, an `op.fish` function intercepts `op` and strips the token inline so daily commands stay biometric and see all your vaults. Net: full multi-vault biometric daily, headless SA-scoped reads in any subprocess, no per-launch wrapper. Requires a 1P Business or Teams plan. Full workflow + analysis: [docs/1password.md](docs/1password.md). For multi-machine setups (e.g. Air + Mini operated mostly over SSH), see [docs/1password-multi-machine.md](docs/1password-multi-machine.md).

## Docs

| Document | What it covers |
|----------|---------------|
| **[docs/llm-dotfiles.md](docs/llm-dotfiles.md)** | The LLM-maintained dotfiles pattern. Shareable, stack-agnostic. Includes setup instructions. |
| **[docs/guide.md](docs/guide.md)** | Full user guide. chezmoi details, manual commands, customization, secrets, multi-machine, troubleshooting. |
| **[docs/secrets-architecture.md](docs/secrets-architecture.md)** | The whole-surface map for the secrets / keys / credentials work. Threat model, credential × device × path matrix, spec-to-slice index, open-questions catalog. Start here if deciding where a future change should go. |
| **[docs/1password.md](docs/1password.md)** | 1Password workflow + analysis. Mental model, dual-mode design, setup, vault tiering, troubleshooting, spec chain. |
| **[docs/1password-multi-machine.md](docs/1password-multi-machine.md)** | Multi-machine extension (Air + Mini-style setup). 4 credential paths, 3 gates, per-environment matrix, iOS SSH support, web3 hardening rule. |
| **[docs/testing.md](docs/testing.md)** | End-to-end test plan for local pattern + lazy secrets. Cross-machine validation steps. |
| **[docs/decisions/](docs/decisions/)** | Architecture decision records (why chezmoi, Fish, Ghostty, 1Password, auto-commit). |
| **[docs/sync-log.md](docs/sync-log.md)** | Sync history. Append-only log of every Claude-assisted sync, hostname-tagged. |

## Credits

Built with [chezmoi](https://www.chezmoi.io/). Inspired by [halostatue/dotfiles](https://github.com/halostatue/dotfiles) and [narze/dotfiles](https://github.com/narze/dotfiles).

## License

MIT
