# Task Backlog: dwarvesf/dotfiles

Updated: 2026-05-09 (S-62 shipped in v0.6.3 patch release)

> **Versioning note:** the next release after v0.6.0 ships as **v0.6.1**, not v0.7.0. Default to patch bumps for incremental sync work, prompt copy-edits, doc syncs, small fixes. Reserve minor bumps (v0.X.0) for genuinely new surfaces or breaking changes. Major bumps (v1.0.0) are reserved for "stable, ready for others." Mostly the repo will keep climbing in patch.

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
- [x] S-51: Multi-machine SA access (`is-login` gate in secrets.fish + `dotfiles secret push` helper to seed remote Keychain; unblocks SSH-driven `op read` on the Mini without breaking S-49 dual-mode on the Air)
  - 2026-05-07 finding: the no-popup SSH/mosh promise is **not delivered**. macOS keychain unlock state is per-Security-Session, not per-user, so SSH and mosh sessions still see a locked keychain even with the GUI logged in. Implementation (gate widening, push helper, `-A` ACL) is correct; backing-store assumption needs a follow-up. See [S-51 errata 2026-05-07](specs/S-51-multi-machine-sa-access.md#errata-2026-05-07).
  - 2026-05-08 resolution: S-53 supersedes the SSH/mosh aspect by moving the SA token to System.keychain (no per-Security-Session unlock) and adding a per-machine SSH-key recipe so outbound `git` works without agent forwarding.
- [x] S-52: Secrets architecture synthesis doc (`docs/secrets-architecture.md`) — the map above the spec chain. Threat model, credential × device × path matrix, spec-to-slice index, open-questions catalog. Backed by `scripts/test-doc-discipline.sh` discipline contract.
- [x] S-53: Headless Mac credential pattern for SSH/mosh — System.keychain SA token + per-machine SSH key. Closes the S-51 errata "Fix space" by picking the System.keychain candidate and pairing it with a per-host github SSH key recipe (1P-generated ed25519, OpenSSH format, base64-piped to `$SECONDARY`). Result: `op` and `git` work over any SSH transport including iOS mosh, no agent forwarding required.
- [x] S-54: `/dotfiles-sync` report uses a delta-inspired, scannable diff layout (single fenced block + `─── emoji Title ───` dividers + organic emoji palette 🌿/🌀/⚠️/👾/🔻/🔸/🍃 + bottom-half decoration: bucket pills, `[N phantom]` boxed counts, ⚪▮ pills, status icons; documents the design that emerged from 2026-05-08 iterations so future prompt edits don't re-litigate)
- [x] S-55: `modify_CLAUDE.md.tmpl` self-emits its idempotency marker (every `chezmoi apply` was duplicating the canonical "Machines / Tool selection / Tech stack" heredoc because the marker was consumed but never emitted; one-line fix in the `else` branch + cleanup recipe to strip accumulated bloat. Mac mini: 1038 lines → stable 403 across 3 applies)
- [x] S-56: Personal preferences move into the dotfiles modify-script (the `# Personal preferences` block — tone/feedback, formatting, visuals, light-theme defaults — was being maintained by hand in `~/.claude/CLAUDE.md` lines 1-32 on every machine, not version-controlled. Moved into `modify_CLAUDE.md.tmpl` heredoc above `# Machines I work from`. Above-marker upstream prefix now collapses to empty. Mac mini: 246 lines stable, 6 canonical headers each appearing exactly once.)
- [x] S-57: `dotfiles ssh audit` strips `OP_SERVICE_ACCOUNT_TOKEN` explicitly so it always queries via biometric (the S-49 op interceptor only strips when `status is-interactive`; the audit is reached from non-interactive contexts where the SA-scoped session can't see Private vault, producing misleading "(no SSH Key items in vault)" + bogus unbacked-key nag. Fix is local to the audit case: 3 `op` invocations now use `env -u OP_SERVICE_ACCOUNT_TOKEN command op`. Mac mini: audit now correctly reports 3 SSH keys in Private and `✓ all 2 disk key(s) have a 1P counterpart`.)
- [x] S-58: Per-machine `Host github.com` block in dotfiles ssh config (S-53 ratify) (the S-53 recipe writes the github block directly to `~/.ssh/config` on the machine; today's broad chezmoi apply clobbered it. Added the block to `home/dot_ssh/config.tmpl` template-conditional on `~/.ssh/id_ed25519_github` existing — fresh machines without S-53 done get 1P agent fallback instead of broken github SSH. Verified on Mac mini: block deploys, idempotent, `ssh -T git@github.com` authenticates as `tieubao`.)
- [x] S-59: Sync `# Machines I work from` table with ops-toolkit canonical updates. Mini hostname `mac-mini-danang` (Tailscale FQDN) per SPEC-002; daemon namespace split (`foundation.d.*` Dwarves-tenant, `mini.*` personal-Mini per dfoundation ADR-0020 + SPEC-054); new iphone row for the SPEC-002 mobile pilot path; substrate pointers updated to `ops-toolkit/tools/{mac-mini-substrate,mac-backup}/`. Verified on Mac mini: 246 -> 248 lines stable across 3 applies; zero em dashes in changed region.
- [x] S-61: `secret-cache-read --batch` collapses N forks into one (~15 ms fish-startup win). Adds a `--batch VAR1 REF1 ...` mode to the cache-read script that resolves N pairs in one bash invocation, emitting NUL-separated `VAR\0VALUE` pairs. Internal two-pass loop resolves OP_SERVICE_ACCOUNT_TOKEN first so subsequent op-read fallbacks have bearer auth. Preserves negative-cache (24h TTL) + `-A` flag from main. `secrets.fish.tmpl` switches to one batched call. Originally drafted as S-55 on `perf/batch-secret-cache`; renumbered S-61 to avoid collision with S-55-claude-md-modify-idempotency. Verified on Mac mini: all 4 secrets populate via new path (lengths check); rendered template fish-syntax clean; shellcheck clean.
- [x] S-62: secret-guard PreToolUse + Stop + PostToolUse hooks (anti-leak). Enforces S-45 ("never echo resolved secret values") against Claude's outbound tool calls. New `home/dot_claude/hooks/secret-guard/{secret-guard,secret-guard-stop,secret-guard-post}.sh` registered for Bash/Read/Edit/Write/MultiEdit (PreToolUse strict block) + same matchers (PostToolUse warn-only on tool_response patterns) + Stop (warn-only on assistant message patterns) via additive merge in `modify_settings.json`. Pipeline rule is **terminal-aware**: a pipeline containing a secret-printing call (op read, op item get, secret-cache-read, security find-generic-password, gh auth token, gpg/openssl decrypt, declare -p, set, python/node/ruby -c) is safe iff capture (`$()` / backticks / `<()`), OR any stdout redirect (`>`/`>>`/`&>`) anywhere in the pipeline, OR last stage in `pbcopy`/`xclip`/`wl-copy`. Nine iterations from v1 (loose) through v3.5 (per-rule guidance + MODE + audit-transcripts) and v3.5.1 (SDD-cleanup pass), shaped by user feedback at each step (paste-token leak, jq false-positives, ultrathink audit, canonical-pattern question, defense-in-depth ask, ergonomic ask, SDD discipline ask). Spec restructured: rules B1-W2 documented uniformly with leak scenario / why / detection / safe form / test IDs; iteration history moved to a Changelog appendix; architecture diagram added; test matrix as category-organized table; cheatsheet anti-pattern catalogue cross-refs rule IDs. Self-contained test runner at `tests/secret-guard.sh` covers 112 cases and passes 112/112 on Hans-Air-M4. New `dotfiles secret-guard` (alias `sg`) CLI with verbs `explain '<cmd>'` / `test` / `log [filter]` / `tail` / `mode {strict|warn-only|off}` / `audit-transcripts` / `doctor`. Audit log at `~/.cache/claude-secret-guard.log` records `[BLOCK|BYPASS|STOP-LEAK|POST-LEAK] [session_id] [tool] reason` with 1 MiB rotation. `home/.chezmoiscripts/run_onchange_after_secret-guard-test.sh.tmpl` runs the matrix on every apply that touches a hook source + prints a first-run banner. Cheatsheet at `docs/secret-handling-cheatsheet.md`. Bypass marker `# secret-guard: allow` for legitimate exceptions; fails open on missing jq or malformed stdin. Tier 3 (other PMs, indirection, base64) and other-surface OOS (NotebookEdit, Task, WebFetch, MCP, PostToolUse content scanning beyond warn-only) documented in spec's Out-of-scope section.

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
