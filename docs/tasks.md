# Task Backlog: dwarvesf/dotfiles

Updated: 2026-05-03 (S-50 shipped)

<!-- Old ID → New ID mapping: F-XX/R-XX/T-XX → S-XX. See docs/specs/S-*.md -->
<!-- S-40 is intentionally unused (number skipped, no spec exists). -->

## Completed (v0.1.0)

- [x] S-01: Idempotent install.sh (--check, --force, exit codes, post-verify)
- [x] S-02: CI smoke test (shellcheck + chezmoi dry-run on macOS, weekly schedule)
- [x] S-03: Bootstrap without git (one-liner in README)
- [x] S-04: Brewfile split (base/dev/apps layers via chezmoi template + headless prompt)
- [x] S-05: Fish dotfiles CLI (13 subcommands)
- [x] S-06: Fish completions for custom functions (8 completion files)
- [x] S-07: Drift detection (dotfiles-drift function + daily startup check)
- [x] S-08: SSH config hardening (1Password agent, IdentitiesOnly, config.d/)
- [x] S-09: Age encryption (dotfiles encrypt-setup guided command)
- [x] S-10: Ghostty image rendering (render-img with chafa + kitty protocol)
- [x] S-11: Decision records (5 ADRs in docs/decisions/)
- [x] S-12: Tag v0.1.0 release
- [x] S-13: Install idempotency refinement
- [x] S-14: CI integration test refinement
- [x] S-15: Secrets fish cleanup (slim secrets.fish.tmpl from 43 to 26 lines)
- [x] S-16: Age encryption guided setup
- [x] S-17: Fish naming consistency (op_env -> op-env, etc.)
- [x] S-18: VS Code extension sync (skip already-installed)
- [x] S-19: Dotfiles doctor
- [x] S-20: Tmux config (C-a prefix, vim nav, fzf picker, project launcher)
- [x] S-21: Consolidate toolchain scripts into install-toolchains.sh
- [x] S-22: Gum TUI onboarding
- [x] S-23: Error message system (gum-styled output, template guards, apply summary)
- [x] Data-driven secret registry (secrets.toml, add-secret, rm-secret, list-secrets)
- [x] Auto-commit workflow (dfe auto-commits, dfs reverse drift sync, ADR-006)

## Completed (post v0.1.0)

- [x] S-25: Starship config polish  - review modules, check Nerd Font rendering
- [x] S-28: README tool showcase icons  - skillicons.dev + shields.io badges
- [x] S-30: Verification loop  - CLAUDE.md rules, subagent, hooks, slash command
- [x] S-31: User guide  - comprehensive manual replacing customization.md
- [x] S-32: Claude-assisted dotfiles sync  - LLM scans drift, reports, syncs on approval
- [x] S-35: Local pattern + lazy 1Password resolution (.local overrides, Keychain cache)
- [x] S-36: Guardrails as managed installer (pin via git tag, npx install)
- [x] S-37: Guardrails upstream release notify (/dotfiles-sync surfaces new tags)
- [x] S-38: SSH key inventory, adoption, and offline backup
- [x] S-39: Dotfiles backup fixes + op_vault resolution consolidation
- [x] S-41: SSH status surfaced in dotfiles doctor
- [x] S-42: 1Password service account token for agent subprocess auth (superseded by S-47)
- [x] S-43: Surface registered-but-uncached secrets in sync + doctor
- [x] S-44: Spec status frontmatter discipline + tasks.md as rolling index
- [x] S-26: Brewfile cleanup  - audit found 1 true duplicate (tldr), font pair clarified as intentional, mise/brew overlap deferred
- [x] S-45: Stop echoing secret values in dotfiles secret refresh (fix after 2026-04-23 leak event)
- [x] S-47: Opt-in `OP_SERVICE_ACCOUNT_TOKEN` via `with-agent-token` wrapper (amended by S-49; daily shell stays biometric)
- [x] S-48: Narrow `chezmoi apply` scope in `dotfiles secret add` / `secret rm` (prevents source/target drift when unrelated managed files have pending changes)
- [x] S-49: Dual-mode `op` via fish interceptor (auto-load token + intercept interactive `op` to strip it; subprocess paths get headless bearer auth, daily shell stays biometric)
- [x] S-50: `/dotfiles-sync` detects user-authored Claude skill drift (one-shot absorbed 8 untracked skills + ongoing core/local/skip prompt for new skills; mirrors Brewfile pattern)
- [x] S-54: Load `OP_SERVICE_ACCOUNT_TOKEN` first in `secrets.fish` so remote-shell cache misses fall through to bearer-auth `op read` (suppresses misattributed `tailscaled` 1P popup on mosh-into-Mini after S-51 + S-53)

## Next up

- [ ] S-24: Ghostty config sync  - convert to template, review settings, add doctor check
- [ ] S-27: Gum UI helper library (lib/ui.sh)  - styled boxes, step progress, validation
- [ ] S-29: VHS terminal demo  - animated GIF of install wizard
- [ ] S-33: Bitwarden secrets backend  - alternative to 1Password, user choice during init
- [ ] S-34: Multi-agent LLM support  - Codex, OpenCode, Cursor alongside Claude Code
- [ ] S-46: Multi-vault tiering for 1P service-account scope  - pattern spec; author's first application recorded in `docs/operations/2026-04-1password-infra-vault-migration.md`. Apply at next SA rotation 2026-07-18 or earlier if an agent workflow needs runtime `op read` on infra creds.

## Backlog (no immediate plans)

- [ ] Aerospace tiling window manager (lightweight i3-like WM for macOS)
- [ ] Multi-machine profiles (chezmoi tags for work vs personal vs server)
- [ ] Per-project Nix flakes (complementary to mise for pinned environments)
