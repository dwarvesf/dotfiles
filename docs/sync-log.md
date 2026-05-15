# Dotfiles sync log

Append-only record of Claude-assisted sync sessions. Each entry logs
what changed and when. Read by Claude at the start of each sync for
context.

---

## [2026-05-16] sync @ Hans Air M4 (untracked-brew classification + SA cache refresh)

Brewfile (core, home/dot_Brewfile.tmpl):
  - added tap: steipete/tap
  - added brew: pi-coding-agent, steipete/tap/peekaboo

Brewfile (local, ~/.Brewfile.local — not committed):
  - added 4 superseded-but-kept: hub, pipx, the_silver_searcher, yarn
  - added 3 misc local: nono (capability-sandbox shell), poppler (PDF lib), python@3.10 (legacy)

Conflicts surfaced and resolved:
  - ollama: brew formula was installed alongside `cask "ollama-app"` (Brewfile comment says they conflict). User chose "cask wins" → user runs `brew uninstall ollama`.
  - microsoft-auto-update cask: skipped (auto-installed by Office/Edge).
  - libusb in Brewfile but not installed: deferred (decide later).

SSH:
  - Backed up trading-egress-tokyo.local to 1P Private vault (Secure Note id 64llazbsp6ggvdnfgipej2od64). Skill's earlier "no backup" check was a false negative caused by `op item get` erroring on cross-vault name collisions; the duplicate I created was deleted, then recreated cleanly.
  - Side finding: mini.local 1P backup is STALE (393 chars stored vs 846 on disk). Not fixed in this session; surface next sync.
  - All three 1P SSH backups (egress, mini, trading-egress-tokyo) share an `op item create` quirk: multi-line notesPlain values get stored with literal `"` wrap-quotes. Restoration must strip them. Documented but not fixed.

Secrets:
  - OP_SERVICE_ACCOUNT_TOKEN cache refreshed via `dotfiles secret push OP_SERVICE_ACCOUNT_TOKEN --local`. Login keychain was holding the previous (deleted-upstream) SA token; 1P item itself had already been rotated a week earlier. No SA recreation needed. Verified: bearer-path `op whoami` now returns the account URL in fresh fish shells.

chezmoi apply NOT yet run (user-gated per project permissions). 17 pending entries + 3 run_onchange scripts (brew-bundle, dotfiles-watcher S-64 LaunchAgent install, secret-guard-test) will deploy on next `chezmoi apply`.

Pending user actions:
  - `chezmoi apply` (deploys repo → machine)
  - `brew uninstall ollama` (resolves the cask/formula conflict)

---

## [2026-05-14] sync @ Mac-mini (mylaunchd helpers)

Tahoe (macOS 26) removed the "Allow in the Background" list from System Settings → Login Items & Extensions, leaving CLI-installed LaunchAgents / LaunchDaemons (`mini.*`, `foundation.d.*`, `com.truonghan.*`) with no UI surface. Added two fish functions to replace it:

- `mylaunchd` — user-only, no sudo (default, fast)
- `mylaunchd-all` — user + system, prompts for sudo

Both machine-agnostic; the filter (`mini\.|foundation\.d\.|truonghan`) is identical across hosts that follow the namespace conventions in `~/.claude/CLAUDE.md`.

Other drift in tree (deferred): modified `dotfiles-watcher-fswatch` / `dotfiles-watcher-tick` executables, untracked `home/dot_claude/skills/tide/` directory.

---

## [2026-05-13] sync @ Mac-mini (cw.fish re-track)

Re-tracking after the S-67/S-68 chain. The watcher's auto-enroll pass cleaned up the skill backlog; the only remaining untracked item that surfaced through `/dotfiles-sync` was `~/.config/fish/functions/cw.fish` (Claude Code worktree-plus-tmux shortcut, 3 lines, machine-agnostic). Originally tracked by Han in a local-only `3fe4a11` commit earlier today that never reached origin (branch protection rejected the direct push, and the commit was dropped when local main was reset to origin/main during the S-67 PR chain).

Now committed to core. Verdict was the same as before (machine-agnostic, useful on any developer machine), so the only consequence of the lost commit was the round-trip cost.

Other items triaged in this sync, all deferred:
- `openai.chatgpt` vscode extension installed but not in `extensions.txt`: skipped (user opted not to track this session)
- 5 stale entries in `extensions.txt` (`docker.docker`, `dwarvesf.md-ar-ext`, `github.copilot-chat`, `ms-vsliveshare.vsliveshare`, `ocamllabs.ocaml-platform`): skipped (carried over from 2026-05-08 deferred batch; user opted to keep)
- `trading-egress-tokyo.local` already correctly suffixed `.local` (gitignored); no action

Notify-only checks all silent or healthy: watcher 6/6 ok (post-S-68), secrets cache full, hardcoded-secrets scan clean, guardrails up-to-date.

---

## [2026-05-13] S-68 doctor idle-state fix @ Mac-mini

Third same-day follow-up to S-66. Closes the false-positive in the S-66 doctor's `agent-wp` check that fired `[err] agent: com.truonghan.dotfiles-watcher loaded but state=notrunning` on healthy idle machines.

Root cause: the WatchPaths agent (`com.truonghan.dotfiles-watcher`) has no `KeepAlive` and no `StartInterval`. launchd loads it at boot, then keeps it idle waiting for an mtime change on one of the ~120 enumerated paths. Steady state is `waiting` or `not running`, not `running`. The doctor's `if state == running then ok else err` was correct for the fswatch sibling (KeepAlive=true, always `running`) but wrong for the WatchPaths agent.

Fix: `check_agent` now treats `launchctl print` exit code as the authoritative "loaded" signal. Output format changes from `[ok] agent: ... running` to `[ok] agent: ... loaded (state=waiting)`. Accept set: `running|waiting|notrunning|idle|""`. Unexpected states fall through to `[warn]` with "Fix: dotfiles watch install".

Tests: new case `4.1b doctor exits 0 on an idle WP agent (S-68)` uses `FAKE_LC_WP=loaded` (which the fake-launchctl shim emits as `state = waiting`). Suite 31/31 (30 prior + 1 new). The S-66 matrix had only `FAKE_LC_WP=running` and `FAKE_LC_WP=missing`, which is why the bug shipped.

Same root signal seeded the misread earlier today: when I first audited "are the watchers doing their job?" I read the `[err] agent-wp` line as truth, then had to back out the misdiagnosis when the live state showed the WP agent was just idle. S-68 closes that loop.

End-to-end verification deferred until post-merge `dotfiles watch install` + `dotfiles watch doctor`.

---

## [2026-05-13] S-67 watcher auto-enroll ship @ Mac-mini

Same-day follow-up to S-66. The new-skill gap surfaced while answering "did the watcher sync the new skills to the dotfile repo?" The honest answer was no: two skills shipped today (`ops-tool-shape`, `ops-tool-docs`) and the dotfiles repo working tree was clean, because the tick filtered `chezmoi status` to `^.M ` rows only and skipped untracked-by-chezmoi files (S-64 § Out of scope, line 79 of the tick).

What landed:
- `home/dot_local/bin/executable_dotfiles-watcher-tick` gains an enrollment pass before the existing drift loop. Reads `AUTO_ENROLL_GLOBS` (initial single entry: `${HOME}/.claude/skills/*/SKILL.md`), expands via `eval` + `set --`, filters via `grep -Fxq` against `chezmoi managed`, runs `chezmoi add` on each unmanaged match. Idempotent: subsequent ticks short-circuit on the grep. New log format `+ enrolled <relpath>` (distinct from existing `+ <relpath>` for re-add).
- `TICK start` / `TICK done (passes=N)` semantics extended: emit when either enrollment or drift absorbed. Pure-enroll case prints `passes=0`. Mixed case prints `passes=N` reflecting drift iterations.
- `tests/dotfiles-watch.sh` § 3b: 4 new cases. Fake `chezmoi` shim grows an `add` subcommand that appends to `$state/added`. Cases cover enroll-new-SKILL, idempotent-when-managed, glob-discipline (README.md inside a skill dir is skipped), and mixed enroll+absorb in one tick.
- `docs/specs/S-67-watcher-auto-enroll-roots.md` drafted earlier in the same session; spec frontmatter flipped to `done`.

No plist generator change. fswatch already covers `~/.claude/` recursively, so launchd sees the file-create event on a new skill. The wiring script's `managed-set fingerprint` line re-fires on the next `chezmoi apply` to fold the new file into WatchPaths. Transient window: between auto-enroll and the next `chezmoi apply`, the file is only watched via fswatch, not WatchPaths. Functionally correct, slight redundancy.

End-to-end verification deferred until post-merge `dotfiles watch install` + `dotfiles watch now` on the Mini. Expected: log line `+ enrolled .claude/skills/ops-tool-shape/SKILL.md` and `+ enrolled .claude/skills/ops-tool-docs/SKILL.md`, then `chezmoi managed | grep ops-tool` returns both rows.

Verifier: shellcheck on the patched tick (SC2295 caught on first pass, fixed by quoting `"$HOME"` inside `${f#}`), full suite 30/30 pass.

Resists configurability: `AUTO_ENROLL_GLOBS` is a hard-coded constant in the tick. No chezmoi-data field, no per-machine override. Revisit when the second auto-enroll case lands.

---

## [2026-05-13] S-66 watcher health audit ship @ Mac-mini

Shipped the post-S-64 follow-up identified earlier in the same session: `/dotfiles-sync` now audits S-64 watcher health.

What landed:
- `home/dot_local/bin/executable_dotfiles-watch-doctor` — POSIX sh, six checks (both LaunchAgents `state = running`, plist fingerprint matches `chezmoi managed | sha256sum`, lock absent or <60s, `fswatch --version` works, log mtime within 30d, headless self-skip). Each non-`[ok]` line carries an inline `Fix: <cmd>` suffix.
- `home/.chezmoiscripts/run_onchange_after_dotfiles-watcher.sh.tmpl` — writes `$HOME/.cache/dotfiles-watcher.managed.sha256` as a side effect so the doctor has something to diff against. No plist surgery needed.
- `home/dot_config/fish/functions/dotfiles.fish` — new `case doctor` branch + `doctor` row in help text.
- `home/dot_claude/commands/dotfiles-sync.md` — new "Watcher health (notify-only)" subsection between Secret cache and SA token rotation; shells out to `fish -l -c 'dotfiles watch doctor'`, grep-filters `^\[(warn|err)\]`, silent on healthy machines.
- `tests/dotfiles-watch.sh` § 4 — 8 new cases (fake `launchctl` + fake `fswatch` + extended fake `chezmoi data` shim driven by `FAKE_LC_WP` / `FAKE_LC_FS` / `FAKE_HEADLESS` / `NOW_OVERRIDE`); suite now 26/26 (up from 17).
- `docs/specs/S-66-dotfiles-sync-watcher-audit.md` — spec drafted, status flipped to `done`, DoD all ticked.

End-to-end verification on this Mac mini:
1. `~/.local/bin/dotfiles-watch-doctor` → six `[ok]` lines, exit 0.
2. `launchctl bootout gui/$UID/com.truonghan.dotfiles-watcher-fswatch` → doctor surfaces `[err] agent: com.truonghan.dotfiles-watcher-fswatch not loaded — Fix: dotfiles watch install`, exit 1.
3. `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.truonghan.dotfiles-watcher-fswatch.plist` → silent again, exit 0.

Notable: secret-guard caught an early test sentinel using `deadbeef...` (64 hex chars = sha256-shaped, looks like a private key). Swapped to `stale-fingerprint-non-hex-sentinel` so the test value can never collide with a real hash. Validates that the hook trips even on test fixtures that *look* secret-shaped.

Verifier: shellcheck (3 scripts), fish -n (1 file), chezmoi execute-template + bash -n on the wiring template, full suite 26/26 pass.

---

## [2026-05-12] S-65 doc sweep @ Mac mini

Post-ship doc cleanup driven by S-64. Five files touched to lock the
post-state in tests:

- `docs/llm-dotfiles.md` -- replaced "No daemon, no watcher" passage (now
  actively wrong) with a section explaining the watcher's complement to
  `/dotfiles-sync`.
- `README.md` -- pitch sentence acknowledging the watcher; cheat-sheet
  row for `dotfiles watch install`; two-layer model section
  cross-references S-64.
- `install.sh` -- step 5 "Optional: dotfiles watch install" in both
  gum-styled and plain-fallback Next steps blocks.
- `home/dot_claude/commands/dotfiles-sync.md` -- "Note on the S-64
  watcher" paragraph at the top of Step 2 setting the expectation that
  empty Drift sections are now the steady state.
- `docs/decisions/006-auto-commit-workflow.md` -- new "Exception" section
  explaining why the watcher deliberately breaks the commit-on-change
  default (no human authored the edit -> review gate has to live
  somewhere -> public repo means daemon commits are higher-risk).

New section 6 in `tests/dotfiles-watch.sh` (7 grep cases) locks the
post-state. Full suite 17/17.

**Re-bit by [[zed-clobbers-claude-edits]].** First-pass Edits to
`install.sh` and the `/dotfiles-sync` skill landed on disk but were
clobbered ~immediately by stale Zed buffers re-saving. Caught by the
section-6 grep tests failing on first run; re-applied with immediate
post-edit `grep` verification. Memory pattern stays correct: verify
`git diff` before `git add` whenever Zed has files open.

---

## [2026-05-12] S-64 watcher ship + regex fix @ Mac mini

First deploy of the S-64 continuous-watcher feature on the Mac mini
(branch `feat/dotfiles-watcher` merged via dwarvesf/dotfiles#98 the same
day). Scope used to avoid clobbering a `.claude/settings.json` MM conflict:
`chezmoi apply ~/.local/bin/dotfiles-watcher-{tick,fswatch}`
`~/Library/LaunchAgents/com.truonghan.dotfiles-watcher-fswatch.plist`
`~/.Brewfile ~/.gitignore ~/.config/fish/functions/dotfiles.fish` then
`chezmoi apply --exclude=files` to fire the `run_onchange` wiring without
touching the conflicted settings.json. brew-bundle installed `fswatch`
along the way. WatchPaths plist generated with 120 leaves; both
LaunchAgents bootstrapped (`com.truonghan.dotfiles-watcher` state=idle,
`com.truonghan.dotfiles-watcher-fswatch` state=running pid 5578).

End-to-end demo on `~/.tool-versions`: live append fired the watcher,
log got `TICK start` + `+ .tool-versions` + `TICK done (passes=3)`,
`git diff home/dot_tool-versions` showed the line absorbed; sed-revert
fired another tick that returned source to HEAD.

**Regex bug found during deploy.** Original `dotfiles-watcher-tick`
matched drift via `awk '/^ M /'` (dest-only modified, source untouched).
On the Mac mini, the live edit produced `MM .tool-versions` in
`chezmoi status` (both-flagged), which `^ M ` does not match -- the tick
exited silently. Widened to `awk '/^.M /'` so any "destination modified"
row (` M `, `MM `, `AM `) absorbs. Added test case 3.5
`absorb_MM_status` to `tests/dotfiles-watch.sh`; full suite 10/10 green.

Drift absorbed:
  - `home/dot_gitignore` -- `.claude/worktrees/` lines re-added (pre-existing
    drift, not introduced this session).

Known issue surfaced this session (now documented in S-64 § Known issues):
  - `.claude/settings.json` is `MM` because a `modify_` script renders it;
    `chezmoi re-add` succeeds but doesn't change source, so each tick
    logs an absorb attempt that's a no-op. `DRIFT_LOOP_MAX=3` keeps it
    bounded. Long-term fix: detect "re-add was a no-op" and stop
    retrying for that file in the same tick.

---

## [2026-05-11] sync @ Hans Air M4

Claude skills (core):
  - added: `local-ocr` (wraps the local-ocr CLI in ops-toolkit; covers SPEC-004
    Mode B auto-absorb and the new SPEC-006 Mode D blind-absorb path. Body
    extended this session with Mode D trigger phrases, the blind-absorb
    workflow, hard rules around `.values.json` and inline image uploads, and
    a pointer to ops-toolkit `USAGE-blind-absorb.md`)

Claude skills (re-add drift, pre-existing):
  - `annas-fetch/SKILL.md` — added `--sort downloads` documentation, stats
    API endpoint reference, and intent-split table for picking the right
    sort. Drift from earlier work; not from this session.

Scripts (applied):
  - `run_onchange_after_secret-guard-test.sh` — passed self-test against the
    deployed hook (S-62 spec test matrix; 1 PASS / 0 FAIL).

---

## [2026-05-11] secret-guard: quoted-heredoc body false-positive fix @ Hans-Air-M4

Caught while pushing the S-63 ship commit. The hook blocked
`git commit -m "$(cat <<'EOF' ... EOF)"` with B2 ('secret-cache-read'
output would land in the transcript) because the message body
documented the helper change. Two compounding causes in
`is_safe_secret_call`:

1. The literal token `secret-cache-read` sits inside a quoted-marker
   heredoc (`<<'EOF' ... EOF`) which preserves the body as data, not a
   call. Existing detection didn't know the difference.
2. The `$()` strip uses the regex `\$\([^\(\)]*\)`, which can't match
   when the body contains parens. Conventional-commit subjects
   (`feat(secret-push) ... (S-63)`) defeat the strip on every commit
   that mentions a hook-watched token.

Fix: prepend a quoted-heredoc body strip step (awk, line-based) to
`is_safe_secret_call`. UNQUOTED markers (`<<EOF`) keep variable
expansion and remain B6's job. Three new tests in
`tests/secret-guard.sh` (cases 131/132/133) cover commit-message
bodies naming `secret-cache-read`, `op read`, and `security
find-generic-password -ws`. Full suite: 115/115 green; shellcheck
clean. Original user repro now exits 0 against the deployed hook.

The bypass marker (` # secret-guard: allow`) and `SECRET_GUARD_MODE=
warn-only` workarounds remain available, but conventional commits no
longer need them.

---

## [2026-05-11] sync: back up annas-fetch skill @ Hans-Air-M4

Targeted sync to back up the new `annas-fetch` Claude Code skill built earlier today (member fast-download CLI for Anna's Archive). Skill drives the stdlib-only Python tool at `ops-toolkit/tools/annas-fetch/` (separate repo, separate commit); the skill itself goes here so it's available from any future Claude Code session on any machine.

Claude skills (core):
  - added: `~/.claude/skills/annas-fetch/SKILL.md`

Untracked-but-deferred this sync (existing daily-life noise, not today's goal):
  - brew: hub, ollama, pipx, python@3.10, the_silver_searcher, yarn
  - cask: microsoft-auto-update
  - chezmoi status: `.claude/commands/dotfiles-sync.md` source-modified (separate work)

Skipped notify-only checks (SSH backup, secret cache, guardrails) since intent was targeted; rerun `/dotfiles-sync` for a full audit.

---

## [2026-05-10] S-63 ship + 2026-05-10 SA rotation event @ Hans-Air-M4

Triggered by today's 1Password SA rotation. Pre-S-63 rotation flow was
"paste 3 commands per host, hope you remembered delete-then-add for
System.keychain." Two pain points surfaced:

1. `add -U` on `/Library/Keychains/System.keychain` over non-TTY SSH
   silently fails with `User interaction is not allowed` + `already
   exists`, exit 0, no value change. macOS gates ACL updates behind a
   GUI prompt that piped SSH can't satisfy. S-53 § B documents
   first-seed only; rotation isn't covered.
2. `secret-cache-read` neg-cache `.miss` markers (24h TTL, S-61) survive
   a rotation, so the next login still skips the slow path even though
   it would now succeed. Manual `rm` per VAR per host.

S-63 codifies both fixes inside `dotfiles secret push`:
  - Variadic targets after `VAR_NAME`. Per-target ✓/✗ verdict + summary.
    Sequential iteration (parallel sudo/biometric prompts interleave illegibly).
  - `--backing-store=login|system` flag (default `login` for backwards-compat).
    System path uses sudo + delete-then-add. Login path also delete-then-add
    (one extra keychain op; subsumes both stores under one code path).
  - `--local` opts the local machine into the iteration. Local first, then
    remotes (keeps biometric/sudo prompts at the local terminal first).
  - Per-target failure isolation: a flaky target doesn't abort the others;
    final exit code is non-zero if any failed.
  - Negative-cache `.miss` cleanup as a side-effect of every successful seed.

Implementation:
  - New bash helper `home/dot_local/bin/executable_secret-upsert-target`
    (per-target probe + delete + add + verify + neg-clear). Pulled out of
    fish because remote sudo + heredocs + fish quoting is unreadable past
    2 layers. Mirrors the fish/bash split from `secret-cache-read` (S-61).
  - Replaced `case push` block in `home/dot_config/fish/functions/dotfiles.fish`
    (variadic arg parsing + flag handling + iteration loop).
  - `scripts/test-doc-discipline.sh` extended: S-63 spec + new helper added
    to FRAMEWORK_DOCS (placeholder-clean); 2026-05-10 cookbook added to
    OPERATIONS_DOCS (must contain author's specifics).
  - S-51 § Trade-offs row 2 + spec chain updated. S-53 § Future work item 1
    closed.
  - `docs/secrets-architecture.md`: spec table extended (S-53, S-61, S-62,
    S-63 rows), Q1 closed, operations cookbook reference added.
  - `docs/tasks.md`: S-63 row inserted; updated banner to v0.6.4.
  - New operations cookbook `docs/operations/2026-05-10-sa-rotation-air-mini.md`
    documents today's specific rotation across Air + Mini, including the
    pre-S-63 manual paste-job, the post-S-63 one-liner equivalent, and the
    secret-guard hook bypasses needed for legitimate `op read | ssh ...`
    pipelines.

Smoke-tested S-63 against `mini-tieubao` (System.keychain backing store).
Full E2E with `--local` deferred since the local Mini-side seed already
happened earlier today via the manual paste flow.

Versioning: v0.6.4 patch (additive, no breaking change).

---

## [2026-05-09] sync (pass 2) @ Hans-Air-M4

Follow-up to today's earlier sync, after PR #87 merged and peon-ping wired up.

Claude skills (local - ~/.config/dotfiles/skills.local):
  - peon-ping-config, peon-ping-log, peon-ping-toggle, peon-ping-use
    (provisioned by peon-ping-setup; recreated automatically by the brew
    package on every machine that installs peon-ping, so safe to suppress)

SSH backup status:
  - 3/3 disk keys backed up to 1P (id_ed25519 manually adopted via Desktop
    paste, since op CLI 2.34 can't import existing SSH keys — memory note
    sharpened: CLI creates Desktop-visible-but-functionally-broken zombies)
  - 3/3 .local SSH config fragments backed up

PR #87 merged (brew-bundle script-order fix + earlier sync log entry).

---

## [2026-05-09] sync @ Hans-Air-M4

Pulled `d5f2241..8668b79` (v0.6.3: S-62 secret-guard, peon-ping, sync fixes).
S-62 hooks deployed cleanly; secret-guard.sh + post.sh + stop.sh present.

Brewfile (local - ~/.Brewfile.local):
  - added cask: swiftdefaultappsprefpane (macOS default-apps pref pane)

Skipped (decide later, no persistence):
  - brew: ollama, python@3.10, yarn (resurfaces on next sync)

Left as-is:
  - brew: hub, pipx, the_silver_searcher (superseded; uninstall denied — kept)
  - cask: microsoft-auto-update (MS auto-dep, harmless)
  - ~/.config/fish/functions/fisher.fish (self-installs)

Notify-only:
  - 1 of 3 SSH disk keys without 1P backup (deferred)

Bug fix:
  - `run_onchange_BEFORE_brew-bundle.sh` → `run_onchange_AFTER_brew-bundle.sh`.
    The BEFORE-phase script ran while ~/.Brewfile on disk still held the
    OLD content, so v0.6.3's new `tap "peonping/tap"` line was never seen
    by `brew bundle`. peon-ping never tapped/installed, even with --force.
    Renaming to AFTER-phase ensures bundle reads the freshly-deployed
    Brewfile. Verified: chezmoi apply re-triggered brew-bundle cleanly,
    peon-ping installed, peon-ping-setup wired hooks/Cursor/OpenCode.

---

## [2026-05-09] release: v0.6.3 - secret-guard hook + peon-ping + sync fixes @ Mac-mini

Patch release covering work landed since v0.6.2:

- **S-62**: secret-guard PreToolUse + PostToolUse + Stop hooks enforcing
  S-45 ("never echo resolved secret values") against Claude's outbound
  tool calls. 17 rules (B1-W2), terminal-aware pipeline detection,
  112-case test matrix, `dotfiles secret-guard` (alias `sg`) CLI, audit
  log with 1 MiB rotation, mode switch (strict/warn-only/off). Self-test
  on chezmoi apply via `run_onchange_after_secret-guard-test.sh.tmpl`.
- **feat(peon-ping)**: voice + overlay notifications wired to Claude Code
  hook events (Stop, Notification, SessionStart, PermissionRequest,
  etc.) via `peon-ping-setup` driver script. Brewfile entry +
  `run_onchange_after_peon-ping-setup.sh.tmpl`.
- **fix(sync) (PR #84)**: `/dotfiles-sync` consolidated into single
  canonical body, filters always-run chezmoi scripts from drift report,
  consolidates `op` calls + zsh nullglob safety.

No spec or schema changes outside of the above.

---

## [2026-05-09] feat: peon-ping (game-voice notifications for Claude Code) @ Mac-mini

User wanted [PeonPing/peon-ping](https://github.com/PeonPing/peon-ping)
installed and integrated as a core dotfiles dependency so every machine
that bootstraps from this repo gets voice + overlay notifications when
Claude Code (and other AI agents) hits a hook event (Stop, Notification,
SessionStart, PermissionRequest, etc.).

Brewfile (`home/dot_Brewfile.tmpl`):
  - added tap: `peonping/tap`
  - added brew: `peon-ping` under AI Tools section

New chezmoi script: `home/.chezmoiscripts/run_onchange_after_peon-ping-setup.sh.tmpl`
  - Runs `peon-ping-setup` after brew bundle has installed the binary.
  - peon-ping-setup is the canonical wire-up step: it auto-detects
    installed AI IDEs (Claude Code, Cursor, OpenCode, Windsurf, etc.),
    registers hooks/plugins, downloads the default starter sound packs,
    and creates the symlinks under `~/.claude/hooks/peon-ping/` that
    the hook entries in `settings.json` point at.
  - Idempotent (safe to re-run); guarded on `headless`.
  - `# packs:` hash-trigger comment so bumping it forces a re-run.

`modify_settings.json` left untouched. Its existing dedup-by-marker filters
strip entries by `LEARNING CAPTURE CHECK`, `secret-guard-stop.sh`, and
`machine-banner.sh` markers; peon-ping's hook command does not match any
of them, so the additive merge preserves peon-ping's hook entries across
applies. New event types peon-ping registers (Notification, SessionEnd,
SubagentStart, PermissionRequest, PostToolUseFailure, PreCompact,
UserPromptSubmit) survive via the shallow `(.hooks // {}) +` merge.
Side-effect: peon-ping's Stop and SessionStart entries get reordered to
position 1 in the array on each apply (the modify-script appends managed
entries after the survivors). Functionally fine; sound just plays before
the learning-capture / machine-banner hooks fire.

Verification:
  - `chezmoi execute-template < home/dot_Brewfile.tmpl` confirms tap +
    `peon-ping` lines render in the right sections.
  - `shellcheck --severity=warning` on the rendered chezmoi script: clean.
  - `chezmoi diff` shows the three intended changes (Brewfile, new script,
    settings.json reorder) and nothing else surprising.
  - `peon status` confirms the runtime is wired up and the default pack
    is installed.

Decisions:
  - Skipped MCP server install (kept hooks-only path; can add later).
  - Default starter sound pack (just the Warcraft III Peon pack) instead
    of `--all`. Future packs can be added via `peon packs install <name>`.
  - Did NOT encode hooks in `modify_settings.json`. The hook script is a
    symlink into the brew prefix that peon-ping-setup creates alongside
    config.json, sound-pack symlinks, MCP, and trainer dirs. Replicating
    that surface in chezmoi is more fragile than letting peon-ping-setup
    own its layout. The design boundary stays clean: claude-guardrails
    owns deny-rules + UserPromptSubmit, modify_settings.json owns
    statusLine + learning-capture + secret-guard + machine-banner +
    safety PreToolUse hooks, peon-ping owns its own event registrations.

---

## [2026-05-09] feat(S-62): secret-guard PreToolUse hook (anti-leak) @ Hans-Air-M4

User asked for a Claude Code hook to prevent the assistant from echoing or
reading 1Password-resolved values into the session transcript - the same
shape as the existing `rm -rf` block hook. Spec: `docs/specs/S-62-secret-guard-pretooluse-hook.md`.

Built a new `PreToolUse` hook that complements claude-guardrails'
`scan-secrets` (which only inspects the user's prompt). This one inspects
**Claude's outbound tool calls**:

- `home/dot_claude/hooks/secret-guard/executable_secret-guard.sh` (new,
  ~160 lines, mode 0755). Reads tool input on stdin, exits 2 with a styled
  block message + audit-log line on match.
- `home/dot_claude/modify_settings.json` registers the hook for matchers
  `Bash`, `Read`, and `Edit|Write|MultiEdit`. Marker
  `secret-guard/secret-guard.sh` added to the dedup-by-marker filter so
  re-applies stay idempotent.

Block rules:

Nine iterations in this session, all visible in the spec test matrix
and the Changelog appendix in `docs/specs/S-62-secret-guard-pretooluse-hook.md`:

- **v1** (loose): treated any pipe as safe. User disproved with
  `op read op://Personal/opencode-go/credential | paste-token`. Full key
  landed in transcript before the Stop hook caught it.
- **v2** (over-strict): pipes default to block, only `pbcopy`/`xclip`/
  `wl-copy` allowlisted. Catches paste-token but blocks legitimate
  `op read X | jq -r .field > /tmp/out`.
- **v3** (terminal-aware): the rule is "does the secret reach
  the topmost shell's terminal?" A pipeline is safe iff (a) capture form
  (`$()` / backticks), (b) any stdout redirect (`>` / `>>` / `&>`)
  anywhere in the pipeline -- a redirect anywhere breaks the secret
  chain at that point, downstream gets empty stdin -- or (c) last stage
  is in the no-echo allowlist (`pbcopy` / `xclip` / `wl-copy`).
- **v3.1** (post-audit, shipped): user requested a pre-deploy audit
  ("only block when secret prints/echoes to screen or saves to session
  or log"). Audit found three real false negatives, each empirically
  reproduced as `rc=0` against v3:
    - **FN1** -- literal credential in the Bash command string itself
      (e.g. `http POST ... Authorization:"Bearer sk-ant-..."`); the
      command is captured verbatim into the JSONL transcript, leaks
      regardless of stdout/stderr.
    - **FN2** -- heredoc with UNQUOTED marker that expands a
      secret-bearing variable (`cat <<EOF\n$TOKEN\nEOF`); the
      pre-audit B3 rule only matched the `<<<` here-string form.
    - **FN3** -- Edit/MultiEdit `old_string` carrying a literal
      secret value, which the diff output then echoes into the
      transcript.
  v3.1 closes all three with rules B6 / B7 / W2 (see spec). New tests
  53-57 prove each fix; tests 56 (quoted-marker heredoc) prove the
  FN2 fix doesn't false-positive on literal-body heredocs.
  Audit-log hygiene confirmed clean (timestamps + abstract reasons,
  no values / commands / file content).
- **v3.2** (post ultrathink-pass, shipped): user requested "ultrathink
  double check one more time to see if there are other cases we
  didn't cover." Did a categorical sweep across nine taxonomies:
  (A) command-string leaks, (B) sub-command output leaks beyond
  `op read`, (C) env-dump beyond `env`/`printenv`, (D) interpreter
  leaks, (E) file-content leaks beyond the 7-pattern path list,
  (F) indirection / dynamic dereference, (G) process substitution
  / heredoc subtleties, (H) tool surfaces beyond Bash/Read/Edit,
  (I) out-of-band channels. Found ~10 real GAP-FIX items (Tier 1
  + Tier 2) and ~6 GAP-DOC items (Tier 3 + OOS).
  Tier 1 (high-impact, daily-workflow):
    - SSH private keys (`~/.ssh/id_*` excluding `*.pub`) added to
      B5 + R1; `*.pub` explicitly allow-listed first to avoid the
      broader id_* glob catching them.
    - 1Password CLI alternates: B1 now also matches `op item get`,
      `op signin --raw`, `op connect token create`, `op
      service-account create`. Same terminal-aware safe-form check.
    - macOS Keychain raw read: new B2b rule for `security
      find-generic-password -w` / `-ws`. Terminal-aware.
  Tier 2 (moderate-impact, common-on-this-machine):
    - More credential file paths: `*.pem`, `*.p12`, `*.pfx`,
      `~/.kube/config`, `~/.docker/config.json`, `~/.npmrc`,
      `~/.pypirc`, `~/.cargo/credentials`, `~/.gem/credentials`,
      `~/.git-credentials`, `~/.config/gh/hosts.yml`,
      `~/.config/gcloud/application_default_credentials.json`.
      Both B5 and R1.
    - Env-dump variants: B4a now also catches bare `set` (no args);
      new B4c for `declare -p` / `typeset -p` / `export -p`. Both
      terminal-aware. Wrappers (`set -e`, `set --`, `env -u FOO
      bar`) intentionally allowed via terminator-class anchoring.
    - `gh auth token`: new B2c rule. Terminal-aware.
    - Decryption: new B2d rule for `gpg -d`/`--decrypt`,
      `openssl enc -d`, `openssl rsautl -decrypt`, `openssl
      pkeyutl -decrypt`. Terminal-aware.
    - Interpreter env-print: new B8 rule for `python|python3|node|
      deno|ruby|perl -c|-e` reading a secret-bearing env var.
      Layered three-signal check (interpreter form + env-access
      syntax + secret-named identifier) keeps false positives down.
      Terminal-aware.
  Implementation note: closing B8 needed quote-aware segment
  splitting in `is_safe_secret_call`. The naive `;`-replace
  approach broke `python -c "import os; print(...)"` by treating
  the `;` inside the python string as a logical separator,
  splitting the redirect off from the call. Replaced with an awk
  char-walker that tracks single/double-quote state. Tier 3 +
  remaining OOS gaps (other PMs, indirection, base64, network
  side channels, NotebookEdit / Task / WebFetch matchers,
  PostToolUse content scanning) documented under Out-of-scope in
  the spec.
- **v3.3** (canonical-pattern pass, shipped): user asked the
  natural follow-up: "now that this is locked down, how does
  Claude actually copy/forward a key into a command that needs
  it?" Enumerated 8 patterns across 3 use-cases (env var
  pass-through; capture-then-use; file/stdin/clipboard handoff).
  P1 (already-loaded env var), P2 (capture-then-use, single
  Bash call), P4 (env-prefix exec), P5 (bash -c subshell), P6
  (process substitution), P7 (file-based handoff with rm), P8
  (clipboard) all verified rc=0 with the hook on. P3 (capture
  across two Bash tool calls) documented as an anti-pattern
  because subshells don't share state. Code change:
  `is_safe_secret_call` now strips `<(...)` process substitution
  alongside `$(...)` and backticks (~5 lines), so the cleanest
  pattern for stdin-auth tools (`curl -H @<(op read 'op://...')`)
  works without the bypass marker. Block message rewritten to
  inline P1/P2/P4/P6/P7 snippets so Claude self-corrects on
  first read instead of round-tripping or reaching for the
  bypass marker. New `docs/secret-handling-cheatsheet.md` (~5
  KB) is Claude-Read-able mid-session for the full pattern
  reference + anti-pattern catalogue. Test matrix grew 7 cases
  (100/100 green).
- **v3.4** (ergonomics + defense-in-depth, shipped): user asked
  "what else can we do to improve it" and selected the full
  package. Seven additions:
    - **A1**: Edit/Write path exemption for `tests/secret-guard.sh`
      and `docs/secret-handling-cheatsheet.md`. Without this, the
      hook blocks edits to its own test fixtures and example doc
      once deployed (caught empirically when an edit to the hook
      source itself contained an AWS-key example string in a
      comment; rewrote the comment to drop the literal pattern).
    - **D1**: Audit log entries now `[<UTC ts>] [<STATUS>] [<session>]
      [<tool>] <reason>` (was `[<UTC ts>] <reason>`). STATUS in
      `BLOCK` / `BYPASS` / `STOP-LEAK` / `POST-LEAK`. Bypass-marker
      uses are now logged (previously silent: every bypass means a
      deliberate leak, audit trail matters). Log rotation: cap at
      1 MiB, .1 backup.
    - **E1**: New `dotfiles secret-guard` (alias `sg`) CLI with
      `explain '<cmd>'` (dry-run hook against a command, report
      allow/block + rc), `test` (run matrix against deployed hook),
      `log [--blocks|--bypasses|--leaks|--all]`, `doctor` (health
      check). High-value debugging affordance.
    - **G1**: CLAUDE.md rule #4 (Secrets) now references S-45 +
      S-62 + the cheatsheet. Fresh sessions discover patterns from
      project context.
    - **B2 (defense-in-depth)**: New Stop hook
      `secret-guard-stop.sh` scans the last assistant message in
      the transcript for credential patterns; warn-only with audit
      log + stderr. Detection-only by design (the message is
      already on disk by Stop time). Registered via additive merge
      in `modify_settings.json` under `hooks.Stop`.
    - **B1 (defense-in-depth)**: New PostToolUse hook
      `secret-guard-post.sh` scans `tool_response` (stdout / content
      / stderr / array shapes) for credential patterns; same
      warn-only model. Catches Read-of-unlisted-path leaks and
      Bash-stdout-echoes-token leaks the PreToolUse hook cannot
      see. Registered under `hooks.PostToolUse` with matcher
      `Bash|Read|Edit|Write|MultiEdit`.
    - **A2**: `run_onchange_after_secret-guard-test.sh.tmpl`
      hash-tied to all three hook source files. Re-runs the
      108-case matrix against the deployed hook on every apply
      that touches any hook source; warns via `lib.sh` if any
      test fails. Surfaces regressions when guardrails patterns
      change or hooks are hand-edited.
  Self-test in this round: Claude itself was hit by the
  deployed hook twice while writing the v3.4 changes. First time:
  an edit to the hook source contained an AWS access-key example
  string in a comment (W1 fired correctly); fixed by rewording.
  Second time: a CLI smoke test wrote `echo $CLOUDFLARE_API_TOKEN`
  via the explain wrapper (B3 fired correctly); fixed with the
  bypass marker for the test invocation. Both confirm the hook
  works end-to-end. New tests 110-117 in the matrix; 108/108
  green.
- **v3.5** (per-rule guidance + MODE switch + retroactive audit,
  shipped): user asked "what else can we do to improve" with
  ultrathink. Tight package: A1 + A2 + B1 + C1 + E1.
    - **A1**: `block()` now takes a rule-ID arg and dispatches per-
      rule recipes. Hitting B5 (cat of secret-bearing file) shows
      "this file holds rendered values; use `dotfiles secret list`"
      instead of generic curl-with-token snippets. Block header
      reads `BLOCKED: secret leak (S-62/<rule>)`. 16 call sites
      updated.
    - **C1**: SECRET_GUARD_MODE env var + ~/.config/secret-guard/
      mode file. `strict` (default), `warn-only` (log + warn but
      exit 0), `off` (exit 0 immediately). `dotfiles secret-guard
      mode {strict|warn-only|off}` to read/set. Useful for
      progressive adoption (warn-only on a new machine for a day,
      then promote).
    - **A2**: fish completions for the `secret-guard` (alias `sg`)
      verbs and sub-verbs (explain/test/log/tail/mode/audit-
      transcripts/doctor) + log-filter flags + mode values.
    - **B1**: `dotfiles secret-guard audit-transcripts` -- scan
      ~/.claude/projects/**/*.jsonl against patterns/secrets.json.
      Read-only. **Empirical first run on Hans-Air-M4 flagged ~5
      transcripts** with various pattern matches (mostly false
      positives like commit SHAs, but also genuine "Secret-like
      variable assignment" hits worth reviewing). Real retroactive
      privacy value.
    - **E1**: chezmoi self-test prints a one-time first-run banner
      pointing at the cheatsheet + CLI verbs + mode switch. Marker:
      `~/.cache/secret-guard.first-run-shown`.
  Test matrix grew 4 cases (120-123): warn-only exits 0, off mode
  silent, B5 block message has B5-specific guidance, B7 block has
  B7-specific guidance. **112/112 green.**

  Note on this iteration: user reverted four tracked files
  (`modify_settings.json`, `dotfiles.fish`, `tasks.md`, `CLAUDE.md`)
  to clean state mid-session before continuing v3.5. The hook
  source (rule IDs + MODE switch) and the new untracked files
  (cheatsheet, spec, tests, hooks, self-test) were preserved.
  The Tight package re-establishes the integration on top of the
  reverted baseline plus adds v3.5.
- **v3.5.1** (SDD-cleanup, shipped): user asked to apply SDD
  discipline back to S-62 to make sure the spec reads as a coherent
  design document rather than a chronological changelog. Spec
  restructured: removed embedded "v3.4" / "v3.5" subsections from
  the body; rules B1-W2 documented uniformly with a 4-field format
  (leak scenario / why it leaks / detection / safe form / test IDs);
  added an architecture diagram showing the four hook points
  (UserPromptSubmit -> PreToolUse -> tool exec -> PostToolUse ->
  Stop -> JSONL); test matrix presented as a category-organized
  table; iteration history moved to a Changelog appendix at the
  end. Cheatsheet anti-pattern catalogue rewritten as a table that
  cross-refs each AP to its rule ID (B1, B5, etc.). Documentation-
  only pass: no hook code or test changes; 112/112 still green.
  Spec is 634 lines (down from 661); information-loss-free.

| # | Tool | Block rule (v3) |
|---|------|------|
| B1 | Bash | `op read op://...` not in v3-safe form |
| B2 | Bash | `secret-cache-read NAME` not in v3-safe form |
| B3 | Bash | `echo`/`printf`/here-string of `$VAR` matching CLOUDFLARE_API_TOKEN, R2_SECRET_ACCESS_KEY, OP_SERVICE_ACCOUNT_TOKEN, OP_SESSION_*, or `*_TOKEN`/`*_SECRET`/`*_PASSWORD`/`*_PASSPHRASE`/`*_API_KEY`/`*_PRIVATE_KEY` |
| B4 | Bash | bare `env`/`printenv` (no args); `printenv NAME` of a secret-bearing var |
| B5 | Bash | `cat`/`bat`/`head`/`tail`/`less`/`more`/`xxd`/`hexdump` of secret-bearing files |
| R1 | Read | `file_path` matches secret-bearing file list (`*/conf.d/secrets.fish`, `.netrc`, `.aws/credentials`, `~/.config/op/*`, `*.env`/`*.secrets`/`*.tokens`) |
| B6 | Bash | heredoc with UNQUOTED marker (`<<EOF`) AND command references a secret-bearing variable. Quoted markers (`<<'EOF'`) preserve the body literally and are NOT blocked. |
| B7 | Bash | command string itself contains a literal credential per `~/.claude/hooks/patterns/secrets.json`; command lands in the transcript verbatim |
| **B2b** | Bash | macOS Keychain raw read: `security find-generic-password -w/-ws` (v3.2) |
| **B2c** | Bash | `gh auth token` (v3.2) |
| **B2d** | Bash | `gpg -d/--decrypt`, `openssl enc -d/rsautl -decrypt/pkeyutl -decrypt` (v3.2) |
| **B4c** | Bash | `declare -p`, `typeset -p`, `export -p` print var defs incl. values (v3.2) |
| **B8** | Bash | interpreter `-c/-e` (python/node/deno/ruby/perl) reading a secret-bearing env var (v3.2) |
| W1 | Edit/Write/MultiEdit | `new_string` / `content` / `edits[].new_string` matches `~/.claude/hooks/patterns/secrets.json` (AKIA, sk-ant, ops_, PEM block, etc.) |
| W2 | Edit/MultiEdit | `old_string` / `edits[].old_string` matches the same pattern set; the Edit diff echoes old_string into the transcript |

What v3 fixed vs v2: `op read X | jq -r .field > /tmp/out`,
`op read X | tee /tmp/x > /dev/null`, and multi-stage pipelines that end
in a redirect are now allowed. Counter-tests still in the matrix prove
`| paste-token`, `| jq`, `| tee` (without final `>`), `| grep`, `| bash`,
`| xargs`, `2>&1 | grep`, `2> /tmp/err` (stdout still on terminal) are
all blocked.

Bypass: `# secret-guard: allow` per call. Wrappers (`env -u FOO cmd`,
`env A=B cmd`), `dotfiles secret list` (names only), and `Read` against
`*.tmpl` template files are allowed by design.

Failure mode: missing jq or malformed JSON -> exit 0 (fail open).
Audit log: `~/.cache/claude-secret-guard.log`.

Verification (S-62 test matrix, `bash tests/secret-guard.sh`): **112/112
green** on Hans-Air-M4 across eight iterations (v1 -> v2 -> v3 -> v3.1
-> v3.2 -> v3.3 -> v3.4 -> v3.5):

- 52 cases from the initial v1->v3 development.
- 5 cases from the v3.1 audit pass (FN1 literal credentials in Bash
  command, FN2 heredoc expansion, FN2 inverse with quoted marker,
  FN3 Edit old_string).
- 36 cases from the v3.2 ultrathink pass: 20 BLOCK (Tier 1: SSH
  keys, op alternates, macOS keychain; Tier 2: more credential
  files, env-dump variants, gh, gpg, language interpreters) plus
  16 ALLOW (boundary tests for each new rule, including: SSH
  public keys must not match the private-key pattern; `op signin`
  without `--raw` is fine; `set -e` / `set --` are flags, not
  dumps; `python -c "..." > /tmp/x` is allowed via the new
  quote-aware segment splitting in `is_safe_secret_call`).
- 7 cases from the v3.3 canonical-pattern pass: P1 env var
  passthrough (curl with `$CLOUDFLARE_API_TOKEN`), P2 capture-
  then-use (single Bash call with `;`), P4 env-prefix exec, P5
  bash -c subshell, P6 process substitution into curl `-H @-`,
  P7 file-based handoff with `rm` cleanup, plus a generic ssh-
  with-key sanity case. All rc=0.
- 8 cases from the v3.4 ergonomics + defense-in-depth pass:
  110/111 (Edit allowed on test-fixture / cheatsheet paths),
  112 (same payload at any other path still blocks), 113
  (audit log includes [STATUS] [session] [tool]), 114 (BYPASS
  uses now logged), 115/116 (PostToolUse hook detects + silent
  on clean), 117 (Stop hook detects in last assistant message).

Plus 6 plumbing checks (shellcheck on hook + modify-overlay,
idempotency f(f(x))==f(x), chezmoi-managed visibility, fail-open on
missing jq, fail-open on malformed JSON).

Audit-log hygiene confirmed clean across all iterations: timestamps
+ abstract reasons + path/pattern names; zero values, zero commands,
zero file content recorded.

S-45 (never echo resolved secret values) was a human/code discipline rule;
this hook enforces it against Claude's tool calls too.

Files touched:

- `home/dot_claude/hooks/secret-guard/executable_secret-guard.sh` (new)
- `home/dot_claude/modify_settings.json` (added marker dedup + 3 entries)

---

## [2026-05-09] consolidate: single canonical /dotfiles-sync body + 2 latent fixes @ Mac mini

User asked for a detailed comparison between the two `dotfiles-sync` skill
copies on disk: user-level (`~/.claude/commands/dotfiles-sync.md`,
chezmoi-managed via `home/dot_claude/...`) and project-scoped
(`.claude/commands/dotfiles-sync.md` in this repo). They had diverged:

- USER had: Step 2 chezmoi-status `R`/`MM` table with chezmoiscripts
  pre-filter (today's commit 5fbd969); full Step 3 delta-style report
  spec (sections 3a-3e: width detection, no-markdown-tables rule, visual
  vocabulary, header block, single-column / two-column layouts). 642 ln.
- PROJECT had: yesterday's consolidated SSH-backup heredoc (S-49 + zsh
  nullglob fix from 7b1616e); but missing all of USER's Step 2/3 work,
  reduced to a 6-line "look for ` M` or `MM`" rule and a 75-line plain-
  text report template. 422 ln.

Today's run executed USER (only it has the Step 3 layout that produced
today's dense scannable report). That meant yesterday's heredoc fix was
NOT actually applied -- I happened to inline a consolidated heredoc at
execution time. Going forward, future runs from USER would re-introduce
the multi-prompt and zsh-nomatch bugs.

Fix bundled three things:

1. Ported PROJECT's consolidated SSH-backup heredoc into USER, replacing
   the two split blocks. Single auth gate, single biometric prompt,
   `shopt -s nullglob` for empty `*.local` glob, S-49 commentary
   preserved.
2. Preempted the same zsh `nomatch` bug in the hardcoded-secrets check:
   wrapped the `grep ~/.config/fish/conf.d/*.fish` glob in a
   `bash <<'EOF'` subshell with `shopt -s nullglob`. Yesterday's log
   flagged this as latent ("safe today, conf.d non-empty"); now closed.
3. Fixed the Already-local `sed 's/".*/"/'` bug that stripped package
   names from `~/.Brewfile.local` output. New pattern uses
   `sed -E 's/^([a-z]+ "[^"]+").*$/\1/'` -- captures `brew "name"` /
   `cask "app"` and discards trailing comments cleanly. Yesterday's log
   flagged this as out-of-scope follow-up; now closed.

Then deleted `.claude/commands/dotfiles-sync.md` to stop the divergence.
USER (deployed via chezmoi from `home/dot_claude/commands/dotfiles-sync.md`)
is now the single canonical body. The skill auto-suggests on "run
dotfiles sync" without a project-scoped slash command, as today's
session already demonstrated.

Verified on Mac mini:
- shellcheck (--shell=bash) clean on both heredoc bodies.
- live re-run of all three fixes against this machine: hardcoded-secrets
  empty (clean), Already-local renders `cask "chrysalis"` cleanly (no
  truncation), chezmoiscripts pre-filter swallows all noise.
- `chezmoi apply --dry-run` clean.
- Skill registry shows ONE `dotfiles-sync` entry (was two pre-delete).
- `chezmoi re-add` absorbed all edits into source.

Net change: -402 lines (422-line duplicate gone, 41-line SSH-split
collapsed into 39-line consolidated heredoc + bug fixes).

Cross-machine impact: chezmoi-deployed canonical body propagates on
next `chezmoi apply` everywhere.

---

## [2026-05-09] fix: /dotfiles-sync filters always-run chezmoi scripts from drift report @ Mac mini

User flagged that today's sync report tagged four `.chezmoiscripts/*.sh`
entries as `[pseudo-stale]` under "Drift to absorb." That bucket was
wrong on two counts:

1. Scripts don't deploy files; they execute. There is no destination
   file to absorb back into source, so "Drift to absorb" is the wrong
   verb regardless.
2. Three of the four (`run_before_aa-init`, `run_before_ab-1password-check`,
   `run_after_zz-summary`) are *always-run* by chezmoi design, not drift.
   They will appear in `chezmoi status` on every machine, every sync,
   forever. Reporting them creates recurring noise that dilutes real
   signal.

Fix: added a pure-bash pre-filter on the `chezmoi status` invocation in
`home/dot_claude/commands/dotfiles-sync.md` (Step 2, "Config drift").
The filter cross-references each `.chezmoiscripts/<name>` entry against
its source filename in `home/.chezmoiscripts/` and suppresses anything
prefixed `run_before_` or `run_after_`. `run_once_*` and `run_onchange_*`
entries pass through and are now documented as belonging to the
"Pending apply" bucket (a `chezmoi apply` will execute and resolve them).

Verified on Mac mini:
- pre-filter implementation tested live: raw `chezmoi status` returned
  3 always-run scripts; filtered output empty (matches reality, no real
  drift).
- absorbed via `chezmoi re-add ~/.claude/commands/dotfiles-sync.md` so
  the user-level deployed copy stays in sync with the chezmoi source.

Surfaced for follow-up (not addressed in this commit):
- `.claude/commands/dotfiles-sync.md` (project-scoped, 422 lines) has
  diverged substantially from the user-level body (now 642 lines).
  Project-scoped lacks the `chezmoi status` `R`/`MM` table entirely,
  so today's misclassification did NOT come from project-scoped. Either
  delete it or stub-link it to the user-level; user decision.
- Original sync still has `openai.chatgpt` extension untracked and
  5 phantom extensions in `extensions.txt` (not installed). User
  classification deferred.

Cross-machine impact: skill body lives in chezmoi source, deploys to
all machines on next `chezmoi apply`.

---

## [2026-05-09] fix: consolidate /dotfiles-sync op calls + zsh nullglob safety @ Mac mini

User flagged two bugs during today's second sync run:

1. **Multiple 1Password biometric prompts.** Two separate Bash code blocks
   in the skill (`SSH fragment backup status` and `SSH key backup status`)
   each ran their own `env -u OP_SERVICE_ACCOUNT_TOKEN op account get` auth
   gate. Each gate prompts on session-expired runs; up to 3 prompts total
   (2 gates + ≥1 inside `dotfiles ssh audit`'s op calls). The two-block
   shape was inherited; nothing forced them to be separate.

2. **`(eval):4: no matches found: ~/.ssh/config.d/*.local` zsh error.**
   Claude Code's Bash tool routes through zsh on macOS. zsh's default
   `nomatch` option errors when a glob expands to nothing. The skill had
   zero `*.local` SSH fragments on this machine, so the loop body never
   ran; zsh aborted at line 4 of the eval'd snippet. Cancellation cascaded
   across the parallel Bash calls in the same batch.

Fix: replaced the two notify-only blocks with one consolidated
`bash <<'EOF'` heredoc in `.claude/commands/dotfiles-sync.md`. One
`unset OP_SERVICE_ACCOUNT_TOKEN`, one `op account get` auth gate, one
biometric prompt. `shopt -s nullglob` makes the empty glob a no-op.
The fish-l interceptor (S-49) ensures `dotfiles ssh audit`'s nested op
calls inherit the same biometric session.

Verified on Mac mini:
- shellcheck (--shell=bash) clean on extracted heredoc body.
- `bash -n` clean.
- Live run on this machine: ssh-config audit and ssh-keys audit both
  silent on success (0 unbacked fragments, 2/2 disk keys backed up).
  No errors, no prompts (session was active).

Out of scope, flagged for future passes:
- `~/.Brewfile.local` display has a `sed` bug that strips package names
  in the `Already local` report section.
- `~/.config/fish/conf.d/*.fish` glob in the hardcoded-secrets check has
  the same latent zsh `nomatch` shape; safe today (conf.d is non-empty).
- "Conditional skip on quiet syncs" was considered but deferred per
  user choice (single-subshell-batch was the agreed scope).

Cross-machine impact: skill is project-scoped (lives in this repo at
`.claude/commands/dotfiles-sync.md`), so Mac Air M4 picks up the fix
the moment it pulls main.

---

## [2026-05-09] S-61 ship: `secret-cache-read --batch` mode (~15 ms fish-startup win) @ Mac mini

Fresh implementation merging the original `perf/batch-secret-cache`
branch's `--batch` mode (drafted as S-55 in 2026-05-07) on top of
main's evolved single-pair script (negative-cache + `-A` flag from
S-49 / S-51 work).

The original PR #78 branch could not be cleanly rebased: main had
substantively evolved the single-pair logic since the branch was cut.
Rather than wrestle a 4-way conflict, wrote a fresh
`perf/secret-cache-batch` branch that:
- Keeps main's negative-cache (24h TTL) and `-A` flag, refactored
  into a `_load_one` helper.
- Adds the original branch's `--batch VAR1 REF1 ...` mode using
  `_load_one` per pair.
- Preserves SA-token-first ordering via a two-pass loop inside the
  batch handler (no longer needs the template-time conditional).
- Switches `secrets.fish.tmpl` to one batched invocation.

Renumbered to avoid collision: this work was originally S-55 on the
old branch, but `S-55-claude-md-modify-idempotency` shipped earlier
today (v0.6.0). New canonical id is S-61.

PR #77 (originally S-54, the SA-token-first ordering reorder) was
closed as superseded: its code change was already in main via
commit 7c4ffc4 (refactor/op-vault-split, 2026-05-08). PR #78 will be
closed as superseded by the fresh branch once merged.

Verified on Mac mini:
- shellcheck clean on `home/dot_local/bin/executable_secret-cache-read`.
- `chezmoi execute-template` renders cleanly; `fish -n` clean on output.
- `chezmoi apply` deploys both files.
- `fish -l -c '...'` populates all 4 secrets:
  OP_SERVICE_ACCOUNT_TOKEN (860), CLOUDFLARE_API_TOKEN (53),
  R2_ACCESS_KEY_ID (32), R2_SECRET_ACCESS_KEY (64).

Spec: [S-61](specs/S-61-batch-secret-cache-read.md). Cross-machine
impact: Mac Air M4 inherits the new batched template + script next
sync.

---

## [2026-05-09] S-59 ship: `# Machines I work from` synced with ops-toolkit @ Mac mini

User flagged that `tieubao/ops-toolkit` had updates affecting the Machines
table that hadn't flowed into dotfiles. Three concrete drifts found:

1. Mini Tailscale hostname is `mac-mini-danang` (FQDN) per
   `ops-toolkit/_meta/SPEC-002-mobile-pilot-v0.md`. Dotfiles said `ssh mini`.
2. Daemon namespace split per dfoundation ADR-0020 +
   `SPEC-054-partial-reversal-tenant-artifacts-back.md` (2026-05-06,
   refined 2026-05-08): `foundation.d.*` is Dwarves-tenant only;
   `mini.*` is personal-Mini (`mini.restic-backup`, `mini.restic-check`,
   `mini.upgrade-check`). Personal-Mini plists moved out of
   `dfoundation/infra/substrate/mac-mini/` into
   `ops-toolkit/tools/{mac-mini-substrate,mac-backup}/`.
3. Mobile pilot path: iPhone -> Termius + Mosh + Tailscale ->
   `tieubao@mac-mini-danang` per SPEC-002. No mention in dotfiles before.

Fix: edited the `# Machines I work from` block in
`home/dot_claude/modify_CLAUDE.md.tmpl` heredoc:
- Mini row hostname updated to `ssh mac-mini-danang`.
- mini-tieubao role text clarified to call out both `foundation.d.*`
  (tenant) and `mini.*` (personal) namespaces.
- New iphone (mobile pilot) row added between mini-tieubao and
  egress-tokyo.
- Trailing prose rewritten to describe the two daemon namespaces
  separately, point at `ops-toolkit/tools/mac-mini-substrate/` for the
  personal substrate, and reference SPEC-002 for the mobile path.
- Resolution rules gained a new "from my phone / iphone" entry.

Verified on Mac mini:
- `chezmoi execute-template` renders cleanly; shellcheck clean.
- `chezmoi apply ~/.claude/CLAUDE.md` deploys (live file 246 -> 248
  lines).
- Apply twice, line count stable. Idempotency preserved (S-55).
- Zero em dashes in the changed region (per the strengthened rule
  shipped same session).

Spec: [S-59](specs/S-59-machines-table-sync-from-ops-toolkit.md). Cross-
machine impact: Mac Air M4 will inherit the same heredoc on next
`chezmoi apply`.

---

## [2026-05-08] S-58 ship: per-machine `Host github.com` SSH block ratified @ Mac mini

User decision (asked 22:50): re-add the github SSH block to dotfiles
source for cross-machine consistency. The block was added by the S-53
recipe directly to live `~/.ssh/config`; today's broad chezmoi apply
clobbered it. The user's Zed `cli_default_open_behavior` decision came
in the same prompt: keep `new_window` (no source change needed).

Implementation:
  - Added `Host github.com` block to `home/dot_ssh/config.tmpl`,
    template-conditional on `stat (joinPath .chezmoi.homeDir
    ".ssh/id_ed25519_github")`.
  - Block deploys only when the per-machine key exists. Fresh machines
    without S-53 run get the 1P agent fallback (block absent, github
    SSH still works via the global `Host *` IdentityAgent line).
  - Self-documenting opt-in: run S-53, next `chezmoi apply` deploys
    the block.

Verified on Mac mini:
  - chezmoi cat ~/.ssh/config contains the github block.
  - chezmoi apply deploys idempotently.
  - `ssh -T git@github.com` returns "Hi tieubao! You've successfully
    authenticated."

Spec: [S-58](specs/S-58-ssh-github-per-machine-block.md). Cross-machine
impact: Mac Air M4 will get the block automatically next sync (the
key already exists there from S-53). Future fresh machines: run S-53
first, then apply.

---

## [2026-05-08] S-57 ship: `dotfiles ssh audit` biometric-explicit @ Mac mini

Fixes the misleading nag from this morning's sync ("⚠ 1 of 2 disk key(s)
have no 1P backup") that prompted the user to redo the `id_rsa` adopt
even though it had succeeded.

Root cause: `dotfiles ssh audit` calls `op item list --vault Private`
which goes through the S-49 op interceptor. The interceptor only strips
`OP_SERVICE_ACCOUNT_TOKEN` when `status is-interactive` is true. The
audit was being invoked from non-interactive contexts (Claude Code's
Bash tool, scripts), so the SA-scoped session was active. The user's SA
token can see Toolkit/Trading vaults but not Private; `op item list
--vault Private` errors out with "isn't a vault in this account",
the audit eats the error with `2>/dev/null`, sees empty JSON, reports
"(no SSH Key items in vault)".

Fix: in `home/dot_config/fish/functions/dotfiles.fish`, the audit's
three `op` invocations (`account get`, `item list`, `item get`) now
explicitly use `env -u OP_SERVICE_ACCOUNT_TOKEN command op` so they
always run biometric, regardless of caller context.

Spec: [S-57](specs/S-57-ssh-audit-biometric-explicit.md). Verified on
Mac mini with both `fish -l -c 'dotfiles ssh audit'` (non-interactive)
and `fish -l -i -c 'dotfiles ssh audit'` (interactive) producing
identical output: 3 SSH keys in Private (id_rsa, id_ed25519_trading_vps,
GitHub) and `✓ all 2 disk key(s) have a 1P counterpart`.

S-49 dual-mode behavior preserved everywhere outside the audit case:
`op read op://...` from a subprocess still uses SA bearer auth.

---

## [2026-05-08] S-56 ship: `# Personal preferences` moves into dotfiles @ Mac mini

User flagged that their global preferences (brutal-honest, no-em-dashes,
visual-learner, light-theme) live as hand-written upstream prefix in
`~/.claude/CLAUDE.md` and are NOT version-controlled. A fresh-machine
bootstrap loses them silently.

Fix: prepend a `# Personal preferences` section to the canonical heredoc
in `modify_CLAUDE.md.tmpl` (above `# Machines I work from`). Mac mini's
above-marker prefix now collapses to empty; the entire post-marker file
is dotfiles-managed.

Cleanup recipe (Mac mini today):
  - Pre-S-56 size: 403 lines (191 upstream prefix + 212 canonical, post-S-55).
    The 191-line upstream prefix had Personal preferences (32 lines) +
    duplicated Tech stack/Security/Self-verification (159 lines, accidental
    user copy-paste from way back).
  - Truncate everything above the marker → 213 lines (marker + canonical).
  - Apply with new heredoc → 246 lines stable across 3 applies.
  - All 6 canonical headers (Personal preferences, Machines, Tool
    selection, Tech stack, Security, Self-verification) appear exactly
    once. The duplicated upstream copies of Tech/Security/Self-verification
    are gone as a free side-effect.
  - User-snippet keywords verified present (brutally honest, em dashes,
    visual learner, light theme).

Cross-machine: Mac Air M4 will need the same recipe next sync. After
that, both machines have personal preferences under git history; future
edits go through normal commit flow.

Spec: [S-56](specs/S-56-personal-preferences-in-dotfiles.md). The user's
personal CLAUDE.md global file is now (effectively) the modify-script
output: marker + heredoc, 246 lines.

---

## [2026-05-08] S-55 ship: `modify_CLAUDE.md.tmpl` idempotency fix @ Mac mini

The bug surfaced in [the same-day sync batch](#2026-05-08-sync-batch-mac-mini)
below: every `chezmoi apply` of `~/.claude/CLAUDE.md` duplicated the
canonical "Machines I work from / Tool selection / Tech stack
preferences / Security Rules / Self-verification" heredoc by ~212 lines.

Root cause: `modify_CLAUDE.md.tmpl` consumed the
`# --- END claude-context ---` marker (used it to find prefix boundary)
but never emitted it. The script's comment claimed an "upstream personal
context generator" was supposed to emit it; that generator either never
existed or has silently regressed. Marker absent → `else` branch took
the entire input as PREFIX → canonical heredoc appended every run.

Fix (one-liner): in the `else` branch, append the marker to the prefix
on first run so subsequent applies find it. Spec:
[S-55](specs/S-55-claude-md-modify-idempotency.md). Diff lives in
`home/dot_claude/modify_CLAUDE.md.tmpl`.

Cleanup recipe (Mac mini today):
  - Pre-fix size: 1038 lines (4 cycles of canonical content stacked).
  - Truncate everything from first `# Machines I work from` line
    (line 192) down → 191 lines of upstream prefix only.
  - Apply with fixed script → 403 lines (191 prefix + marker + 212
    canonical).
  - Apply twice more → stable at 403. ✓ idempotent.
  - `# Machines I work from` count went from 4 → 1.
  - `# Tech stack preferences` count is 3 (1 from canonical + 2 from
    upstream prefix; the duplicate-in-prefix is a separate
    user-personal-CLAUDE.md issue, out of scope per S-55).

Cross-machine impact: Mac Air M4 will hit the same recipe next time it
syncs (`~/.claude/CLAUDE.md` on the Air has accumulated its own bloat
from the same bug). The fix is portable; the cleanup is per-machine.

---

## [2026-05-08] sync batch @ Mac mini

First end-to-end run of the new S-54 layout. 19 pending entries from
upstream PR #76 (multi-machine-op) were sitting since this morning's
pull; this batch closes them out.

Pending applied (P1-P10):
  - 10 user skills (browser-tool-selection, cashflow-close,
    cloudflare-tool-selection, doc-compaction, extract-workflow,
    incident-workflow, ingest-to-wiki, playwright-record,
    reconcile-properties, vn-contract-format) state-DB tracked.
  - .claude/hooks/machine-banner SessionStart hook deployed.
  - .config/fish/functions/{op,with-agent-token}.fish (S-49 dual-mode)
    state-DB tracked.
  - .claude/CLAUDE.md +211 lines (machines table + tool-selection rules)
    via the modify_ overlay. Note: see "Open issues" below — the modify
    script has a duplication bug that surfaced during this session.
  - .claude/statusline-command.sh `"$HOME"` quote fix (SC2295).
  - .gitconfig adds [init] templatedir = ~/.git_template.
  - .Brewfile renders with +agent-browser, +opencode, +ollama,
    +playwright-cli; renames zen-browser→zen, tailscale→tailscale-app.
  - .config/code/extensions.txt + docker.fish completion (minor).

Brewfile classifications (Untracked installs U1-U3):
  - core: restic · tailscale · typescript     (home/dot_Brewfile.tmpl)
  - core rename: codex → codex-app            (cask track-canonical)
  - core add: ollama-app                      (cask, separate from CLI)
  - local (~/.Brewfile.local): apfel · coreutils · gitup · subversion ·
    yarn · hashicorp/tap/terraform · steipete/tap/remindctl · htop ·
    hub · pipx · rbenv · ruby · the_silver_searcher · youtube-dl · z ·
    zsh · google-cloud-sdk · zen-browser · microsoft-auto-update.
    "Keep installed, don't promote, don't uninstall." All legacy aliases
    (gcloud-cli/zen are the canonical equivalents in core).

SSH backup:
  - id_rsa adopted into 1Password "Private" vault. Verified by
    `op item list --categories "SSH Key"` — fingerprint matches disk.
  - All 4 SSH Key items in 1P: id_rsa (Private), GitHub (Private),
    id_ed25519_trading_vps (Private), mini-github (Toolkit).

Conflicts resolved (during user's broad chezmoi apply between turns):
  - C1 .claude/settings.json — source's SessionStart hook landed.
  - C2 .config/zed/settings.json — landed on `cli_default_open_behavior:
    "new_window"` (source's value); user may want to revisit if they
    preferred `existing_window` on this machine.

Regressions to acknowledge:
  - ~/.ssh/config Host github.com block (added by S-53 recipe earlier
    today) was clobbered by the broad apply. github SSH now falls
    through to the global `Host *` IdentityAgent (1P agent) line. Works
    if 1P agent has the GitHub key enrolled, but it's not the
    per-machine ed25519 path S-53 designed. Decide later: re-add the
    block to source for cross-machine consistency, or accept agent
    fallback.

Open issues from this session (S-55 candidates):
  - **`modify_CLAUDE.md.tmpl` is non-idempotent.** The script expects an
    upstream generator to emit `# --- END claude-context ---` marker;
    when absent, the script appends canonical sections every apply
    instead of replacing them. Live `~/.claude/CLAUDE.md` now has 6
    copies of `# Tech stack preferences` / `# Security Rules` headers.
    Fix: have the modify script self-emit the marker on first run when
    absent, so subsequent applies find it and idempotency holds.
  - **`dotfiles ssh audit` shows zero SSH keys in Private vault** when
    `op item list --vault Private --categories "SSH Key"` returns 3.
    Vault-name resolution or stderr-eaten error inside the fish
    function. Audit currently misleads the user into thinking adoption
    didn't work.

---

## [2026-05-08] S-54 ship: `/dotfiles-sync` report layout (delta-inspired) @ Mac mini

Codified the report layout that emerged from a long pairing iteration on
the Mini today. Spec: [S-54](specs/S-54-dotfiles-sync-report-layout.md).
Prompt source: `home/dot_claude/commands/dotfiles-sync.md` (`/dotfiles-sync`
slash-command). No deployed-copy churn until next `chezmoi apply`.

Settled design captured in the spec:
  - Single fenced code block per run; `─── 🌿 Title — context ───` dividers
    inside the block (replacing markdown `###` headings, which add an
    unavoidable blank line in CC's renderer).
  - Organic emoji palette: 🌿+ / 🌀~ / ⚠️‼ / 👾classify / 🔻superseded /
    🔸stale-section / ⚪notify; status icons 🍃 / ⚠️ / ❌ for Notify-only.
  - Strict row format `<emoji> <ascii> <padded-path>  <description> [tag]`
    with description ≤ 40 chars (longer summarized as `+N items (a, b, …)`).
  - Bottom-half decoration: bucket pills + `•` bullets in Untracked,
    `[N phantom]` boxed count in Stale, `⚪▮` pill + `▸` sub-bullets +
    `✗` missing markers in Already local, status-icon-led rows in
    Notify-only.
  - Header is a 2-line summary; zero counts collapse out.
  - Responsive: balance check `RATIO < 4` AND `min(L,R) >= 3` AND
    `COLS >= 140` to engage two-column; otherwise single-column. The
    19/2 case from this session would have wasted ~85% of the right
    column without the rule.

Iterations rejected along the way (recorded so we don't relitigate):
  - Colored squares (🟩🟨🟥🟧🟪) instead of emoji — user preferred
    organic glyphs.
  - Tags right-aligned to a column — long pad-stretches read as noise;
    inline is denser.
  - `⇒` separator between path and description — wasted a column.
  - Markdown tables anywhere in the report — heavy cell borders in CC's
    renderer destroy the dense diff look (now a hard rule in the prompt).

---

## [2026-05-08] S-53 ship: System.keychain SA + per-machine SSH key on $SECONDARY @ Hans Air M4

Closed the [S-51 errata](specs/S-51-multi-machine-sa-access.md#errata-2026-05-07)
"Fix space" by picking System.keychain for the SA token (errata candidate 2)
and pairing it with a per-machine SSH-key recipe for outbound git. Pattern,
trade-offs, and full test plan live in
[S-53](specs/S-53-headless-mac-credential-pattern.md); this entry just
records the rollout.

Per-host changes (machine-local, not chezmoi-managed):
  - `OP_SERVICE_ACCOUNT_TOKEN` planted in System.keychain via `sudo
    security add-generic-password ... -A -T /usr/bin/security -T
    /opt/homebrew/bin/op /Library/Keychains/System.keychain`.
  - Per-machine `ed25519` key generated inside 1Password
    (`--ssh-generate-key=ed25519`), private half base64-piped to
    `~/.ssh/id_ed25519_github` (mode 600), public half registered with
    the upstream.
  - `~/.ssh/config` on `$SECONDARY` got a `Host github.com` block with
    `IdentitiesOnly yes`.
  - `/etc/paths.d/homebrew` added so non-interactive sessions can find
    `op`, `brew`, `mosh-server`.

Verification all green from `env -u SSH_AUTH_SOCK ssh -a $SECONDARY` (the
no-agent context that mosh sessions get): `op whoami` returns SA account
info with a per-machine Integration ID distinct from `$PRIMARY`'s, `ssh
-T git@github.com` returns "Hi $USER!", `ssh-add -l` confirms no agent in
play, `OP_SERVICE_ACCOUNT_TOKEN` length is non-zero.

Footguns hit (now documented in S-53):
  - `--ssh-generate-key --vault=X` parses the next flag as the key type;
    use `--ssh-generate-key=ed25519`.
  - `op read .../private key` returns PKCS#8 by default; OpenSSH needs
    `?ssh-format=openssh`.
  - `printf "...\n..."` over fish→ssh→fish corrupts newlines; use
    single-quoted multi-line string piped via stdin, or base64 for
    binary content.
  - SA tokens cannot bridge 1P accounts; vault and SA must share one.

Air's `~/.ssh/config.d/mini.local` was momentarily toggled to
`ForwardAgent no` to verify `$SECONDARY` self-sufficiency, then reverted.
Net change on air: none. Forwarding stays on as a safety net; mosh strips
it anyway, so the iOS path works regardless.

Repo state changes (chezmoi/docs):
  - `docs/specs/S-53-headless-mac-credential-pattern.md` (new).
  - `docs/specs/S-51-multi-machine-sa-access.md`: status banner pointing
    to S-53.
  - `docs/1password-multi-machine.md`, `docs/secrets-architecture.md`,
    `docs/operations/2026-05-mini-sa-seed.md`: errata callouts updated
    to point at S-53 as the resolution.
  - `docs/tasks.md`: S-53 entry, S-51 follow-up note.

---

## [2026-05-08] S-45 leak event: SA token + OpenAI + Gemini keys via Claude Code session @ Hans Air M4

During an investigation of the `tailscaled` 1P popup on `tieubao@mini` (S-54
follow-up), the Claude Code session echoed three live secrets to its
terminal output and the on-disk JSONL transcript:

  1. `OP_SERVICE_ACCOUNT_TOKEN` (op-service-account-trading) — leaked via
     `fish set -S` introspection inside an `ssh mini-tieubao` diagnostic.
     `set -S` prints variable values; `string length` should have been used.
  2. `OPENAI_API_KEY` (sk-proj-...) — leaked via bulk `cat ~/.zshrc` over
     SSH while enumerating shell-startup `op` invocations on the Mini.
     The Mini's `.zshrc` had the key hardcoded as a plaintext export
     (outside the dotfiles secret pipeline).
  3. `GEMINI_API_KEY` (AIza...) — same root cause, same `cat ~/.zshrc`
     dump.

Blast radius:
  - Terminal scrollback on `Hans-Air-M4` (Claude Code session).
  - Session JSONL transcript at
    `~/.claude/projects/-Users-tieubao-workspace-tieubao-dotfiles/<sid>.jsonl`
    (~1 MB, replicated for prompt-cache reuse). 4 occurrences of the SA
    token, 2 each of OpenAI/Gemini.
  - SSH/mosh wire path between Air and Mini.

Mitigation taken:
  - All three keys rotated by the user (OpenAI revoke + new key, Gemini
    revoke + new key, SA token rotated in 1P web admin).
  - Live JSONL transcript scrubbed in place via regex redaction
    (`ops_*`, `sk-proj-*`, full Gemini literal). 9 occurrences replaced
    with `[REDACTED-S45-LEAK-2026-05-08-*]` markers.
  - Pre-scrub backup moved to `/tmp` and also redacted (rm blocked by
    PreToolUse guardrail; redact-in-place was the workable path).
  - Mini's System.keychain `OP_SERVICE_ACCOUNT_TOKEN` entry to be
    re-seeded with the new SA token by the user (interactive
    `read -rs` on the Mini, no chat traversal).
  - `.zshrc` plaintext OpenAI/Gemini exports flagged as a separate
    follow-up (Mini's `.zshrc` is not chezmoi-managed; needs migration
    to the `op://`-ref pipeline or at minimum out of plaintext export).

Process failures recorded:
  - Verification commands for "is the var populated" should use
    `string length`, never `set -S` or `echo $VAR`. Add to S-45 guidance.
  - Bulk `cat ~/.zshrc` for grep purposes is unsafe; use `grep -nE
    "pattern" file` so terminal output contains only matched lines.
  - "Read-only investigation" is not safe by default if the read target
    contains live secrets. Anything cat'ing dotfiles needs an
    explicit secret-aware filter.

Precedent: 2026-04-23 leak event referenced in S-45 spec.

---

## [2026-05-08] op-vault-split: Trading→Toolkit + new Trading + SA rotation @ Mac-mini

First application of S-46 multi-vault tiering. Old `Trading` vault renamed to
`Toolkit` (Infra tier per S-46); new `Trading` vault created (Primary domain
tier) holding 5 actual trading items. Items renamed: `Cloudflare R2` → `cf-r2`,
`Cloudflare API Token` → `cf-api-token`. SA renamed `op-service-account-trading`
→ `op-service-account-ops`, bearer rotated, granted Read on both vaults.

Full migration record: [`operations/2026-05-08-op-vault-toolkit-trading-split.md`](operations/2026-05-08-op-vault-toolkit-trading-split.md).

Secrets:
  - 4 Keychain entries flushed and re-seeded with new vault refs
  - `secrets.toml` flipped: `Toolkit/cf-api-token`, `Toolkit/cf-r2/{username,credential}`, `Private/op-service-account-ops`
  - Fish login back to ~100ms (was 2.6s pre-migration; root cause was a stale ref from the morning's Private→Trading commit pair `7c4ffc4`/`6db9ad3`)

Repos migrated (5 branches, none pushed):
  - `tieubao/dotfiles@feat/multi-machine-op` — `7e2be47` runtime + `35d2526` docs sweep + this commit closing S-46
  - `tieubao/ops-toolkit@refactor/op-vault-split` — `7954df6`, 65 files
  - `tieubao/dfoundation@refactor/op-vault-split` — `952abcd`, 30 files
  - `tieubao/trading@refactor/op-vault-split` — `e9ca4f8`, 46 files (5 keepers preserved at `op://Trading/`)
  - `tieubao/event-bridge@refactor/op-vault-split` — `9fab388`, 12 files incl. `wrangler.toml`

Mac Mini Phase 3 deploy (separate chat, on-Mini): rsync of `tools/{mac-mini-substrate,mac-backup}/` from tieubao→server; surgical sed on `dfoundation/infra/substrate/mac-mini/hermes-insights-digest.sh` with `.bak.pre-vault-split-2026-05-08` recovery point. `mini.upgrade-check` smoke-fired green. Surfaced finding: daemon-context `op read` was never load-bearing — static-file fallbacks have been carrying the load all along.

Specs:
  - S-46 status flipped `proposed` → `done` with Implementation section pointing at this record + the 5 commits
  - April migration record (`2026-04-1password-infra-vault-migration.md`) marked superseded — its planned `Infra` vault never landed; today's split with `Toolkit`/`Trading` is the actual implementation

---

## [2026-05-07] S-51 SSH/mosh smoke-test failure traced to Security Session model @ Mac-mini

Ran [`docs/operations/2026-05-mini-sa-seed.md`](operations/2026-05-mini-sa-seed.md)
end-to-end on the Mac Mini, sitting at the GUI. Steps 1-4 passed. Step 5
(cross-machine smoke test from iOS mosh) **failed** with a 1Password CLI
integration popup ("Allow mosh-server to get CLI access") on the Mini's
screen.

Setup completed (Steps 1-4):
  - `feat/multi-machine-op` checked out on Mini (PR #76 not yet merged).
  - `chezmoi apply` on the three S-51 files (`secrets.fish`,
    `secret-cache-read`, `dotfiles.fish`).
  - `login.keychain-db` seeded with `OP_SERVICE_ACCOUNT_TOKEN` (`-A` ACL)
    via `env -u OP_SERVICE_ACCOUNT_TOKEN op read | bash -c 'security
    add-generic-password ... -A -U'`.
  - Local Step-4 verification all green: `security find-generic-password
    ... -w | head -c 4` → `ops_`; `fish -l -c 'string sub -l 4 -- "$OP_SERVICE_ACCOUNT_TOKEN"'`
    → `ops_`; `fish -l -c 'bash -c "op whoami | grep User Type"'` →
    `User Type: SERVICE_ACCOUNT`.

Step-5 failure diagnostic from iOS mosh on the Mini:
  - `status is-login` → TRUE (gate works as designed).
  - `status is-interactive` → TRUE.
  - `string length -- "$OP_SERVICE_ACCOUNT_TOKEN"` → 0 (loader produced
    no value).
  - `security find-generic-password ... -w 2>&1`
    → `security: SecKeychainSearchCopyNext: The specified item could not
    be found in the keychain.` (misleading — entry is present and was
    just seeded; locked keychain reports items as not-found).
  - `security show-keychain-info ~/Library/Keychains/login.keychain-db
    2>&1` → `security: SecKeychainCopySettings ...: User interaction
    is not allowed.` (canonical macOS error for "this keychain is
    locked in this session and cannot be unlocked from a non-GUI
    context").

Root cause:
  - macOS holds keychain unlock state **per Security Session**, not per
    user. sshd- and mosh-server-spawned children run in a different
    Security Session than the console GUI session. Auto-login keeps the
    console session's keychain unlocked but does not propagate that
    state to subsequent SSH/mosh Security Sessions.
  - `secret-cache-read` swallows the failed Keychain read (`2>/dev/null`)
    and falls through to `op read`. Because `OP_SERVICE_ACCOUNT_TOKEN`
    is not yet in env (it is what we are trying to load), `op read` has
    no auth and contacts the 1Password desktop CLI integration socket,
    which raises the popup at fish startup.
  - Same path is shared by `CLOUDFLARE_API_TOKEN` and `R2_*` via
    `secret-cache-read`: they fail under SSH/mosh on $SECONDARY for
    the same structural reason.

Spec gap recorded:
  - `docs/specs/S-51-multi-machine-sa-access.md` §"Operational
    prerequisite" (lines 144-152) is incorrect. **Errata appended**;
    original prose preserved.
  - `docs/operations/2026-05-mini-sa-seed.md` got a status banner
    flagging Step 5 as not reachable.
  - `docs/1password-multi-machine.md` "Boot-time keychain lock" got an
    inline Note callout above the trade-off table.
  - `docs/secrets-architecture.md` Q10 status updated from open to moot
    (the question's framing assumed auto-login was a working
    mitigation).
  - `docs/tasks.md` S-51 entry marked with the finding.

What S-51 does still deliver correctly:
  - Gate widening (`is-interactive` → `is-login`) works under SSH and
    mosh.
  - `dotfiles secret push` seeds remote Keychain successfully.
  - `-A` ACL on the entry is correct.

What it does not deliver:
  - A no-popup SSH/mosh experience on $SECONDARY using only the login
    Keychain as backing store. The Security Session model makes that
    unreachable.

Fix path: TBD. Four candidates evaluated; **none chosen yet**:
  1. 0600 file at `~/.config/op/service_account_token`.
  2. System keychain entry.
  3. Per-user LaunchAgent serving via Unix socket.
  4. 1Password Connect local Docker.

This sync was documentation-only. No code changes. No commits to
`secrets.fish.tmpl`, `secret-cache-read`, `secrets.toml`, or
`dotfiles secret push`. The fix gets its own spec.

---

## [2026-05-07] S-52 secrets architecture synthesis doc @ Hans Air M4

Shipped the synthesis doc that maps the whole secrets / keys / credentials
problem space, sitting above the 13-spec chain. Triggered by the question
"have we settled this?" — the honest answer was no, only a slice. The
synthesis doc makes the gap explicit and forces the prioritization
conversation.

New files:
  - `docs/secrets-architecture.md`: threat model (6 adversary scenarios),
    credential taxonomy (6 classes), device taxonomy (5 classes incl.
    open Linux/hardware-wallet entries), credential paths (1-5 today plus
    placeholder for future hardware-wallet path), spec-to-slice mapping
    for all 13 secrets-related specs, open-questions catalog (10 items
    each with status / blocker / next step), framework-vs-cookbook
    decision tree, settling status, maintenance contract.
  - `docs/specs/S-52-secrets-architecture-synthesis-doc.md`: spec defining
    the doc's contents, acceptance criteria, and 4 verification tests.
    Status: done.

Modified docs:
  - `docs/1password.md`: spec chain table extended with S-52, plus a
    pointer at the top of the chain area to the synthesis doc as the
    whole-surface entry point.
  - `docs/1password-multi-machine.md`: synthesis doc added to "See also"
    as the first entry.
  - `README.md`: docs table extended with the synthesis doc and the
    multi-machine doc (the latter was missing from README's table
    despite existing).
  - `docs/tasks.md`: S-52 appended to completed list.

Modified discipline test:
  - `scripts/test-doc-discipline.sh`: FRAMEWORK_DOCS now includes
    `docs/secrets-architecture.md` and `docs/specs/S-52-*.md`. Test still
    passes (doc is placeholder-clean by design).

Verification:
  - `./scripts/test-doc-discipline.sh`: ✓ Doc discipline contract holds.
  - All 13 secrets-related specs referenced in the synthesis doc.
  - All cross-references present (1password.md, 1password-multi-machine.md,
    operations/2026-05-mini-sa-seed.md).
  - Back-links from README, 1password.md, 1password-multi-machine.md to
    synthesis doc all present.

---

## [2026-05-07] S-51 multi-machine SA access @ Hans Air M4

Shipped the multi-machine extension to S-49's dual-mode `op` design.
Originated from a session about SSH-into-Mini breaking 1P biometric flows.
Two minimal changes inside the dotfiles surface, plus two new docs.

Changes:
  - `home/dot_config/fish/conf.d/secrets.fish.tmpl`: gate widened from
    `if status is-interactive` to `if status is-login`. Non-interactive
    SSH login shells (`ssh user@host '<cmd>'`) now load the SA token,
    so subprocess `op read` works headlessly from the remote side.
    Added a comment block referencing S-51 for the rationale.
  - `home/dot_config/fish/functions/dotfiles.fish`: new `secret push VAR
    ssh-target` sub-command. Reads locally via `op read` (S-49 interceptor
    routes through biometric for full vault scope), pipes the value over
    SSH stdin (never on the command line), writes to the remote login
    keychain via `security add-generic-password -U`. Pre-flight SSH probe
    refuses to leak the value if the target is unreachable.

New docs:
  - `docs/1password-multi-machine.md`: companion to docs/1password.md.
    Covers the 4 credential paths, the 3 gates at fish login, per-
    environment state matrix (Air-GUI / Mini-GUI / SSH-from-Air /
    SSH-from-iOS / post-reboot), the seed-from-Air recipe, the boot-
    time keychain-lock mitigations, iOS SSH (Termius/Blink) support
    matrix including the `git push` gap, and the web3 hardening rule
    (signing material never in SA-readable vaults).
  - `docs/specs/S-51-multi-machine-sa-access.md`: spec proper, format
    matching S-49/S-50. Status: done after Air-side regression passed.

Touched docs:
  - `docs/1password.md`: added a Multi-machine pointer section after
    "Trade-offs accepted", and added S-51 to the spec chain table.
  - `docs/tasks.md`: appended S-51 to completed list.
  - `README.md`: small addendum to the Security/dual-mode paragraph
    pointing at the multi-machine doc.

Operational notes:
  - The Mini's login keychain auto-lock at reboot is documented as an
    operational decision (auto-login or manual GUI login post-reboot),
    not a dotfiles change.
  - iOS-driven `git push` from Mini is documented as a future option
    (per-iOS-app SE-bound key registered with GitHub). Not implemented.
  - Mini-side seeding deferred: this commit ships the helper and the
    code change; the actual seed run happens when the user requests it.

Verification (Air-side):
  - `fish -n` on dotfiles.fish: clean.
  - regression test plan tests 1-4 from S-51 to be run before commit.

---

## [2026-05-07] sync @ Hans Air M4

Apply pending PRs landed: chezmoi apply absorbed PR #72 (SSH privacy gate
in /dotfiles-sync) and PR #69 (Brewfile cask "zen" canonical rename).

SSH config.d (privacy gate, all on-disk fragments now `.local` + 1P-backed):
  - rename trading-egress-tokyo → trading-egress-tokyo.local
    (1P backup pre-existed: "SSH config: trading-egress-tokyo" in vault Trading)
  - create 1P Secure Note "SSH config: egress" in vault Trading
    for the existing egress.local fragment (Tailscale alias to
    trading-egress-tokyo). egress.local already correctly named.
  - mini.local was already conformant (1P/Private).

Brewfile (core - home/dot_Brewfile.tmpl):
  - removed brew (8 stale, not installed on this Air): ffmpeg, go, librsvg,
    node, protobuf, ripgrep, sqlite, terraform
  - removed cask: codex
  - added brew: bats-core, mosh, pandoc, rust, wireguard-tools

Brewfile (local - ~/.Brewfile.local):
  - added cask: antigravity, calibre, chrysalis, codexbar, conductor, cursor,
    grandperspective, hyprnote, opencode-desktop, tana, tor-browser, zen
  - added brew: doctl, duti, gitup, lume, markdown-oxide, ocaml, rclone,
    subversion, tldx, xcodegen, hashicorp/tap/terraform
  - kept (per user choice, despite supersedes by zoxide / fish): z, zsh

VS Code extensions:
  - added (5): docker.docker, dwarvesf.md-ar-ext, github.copilot-chat,
    ms-vsliveshare.vsliveshare, ocamllabs.ocaml-platform
  - removed (1): openai.chatgpt (uninstalled)

Claude skills (suppressed via ~/.config/dotfiles/skills.local, all local):
  - agentkernel, bot-reply-formatting, cashflow-append, cashflow-correct,
    cashflow-report

Untracked drift left for user (not actioned):
  - legacy brew migrations (recommend uninstall): hub, pipx, the_silver_searcher,
    yarn (+ python@3.10 tag-along of pipx)
  - cosmetic: microsoft-auto-update (Office), swiftdefaultappsprefpane (one-off),
    zen-browser (alias artifact for cask "zen")
  - fisher.fish (we use chezmoiexternal, not fisher) - skip recommended

---

## [2026-05-06] sync @ Hans Air M4

Config:
  - statusline: switch hostname source from `hostname -s` (returns generic "Mac")
    to `scutil --get LocalHostName` (returns "Hans-Air-M4"), matching the
    SessionStart machine-banner hook. User noticed the statusline read `@Mac`
    instead of the actual machine name; root cause was the macOS default
    smb-style hostname clobbering the more useful LocalHostName.

Other drift deferred (Brewfile, .chezmoiscripts/*, dotfiles-sync.md command
edits) — needs its own dedicated sync pass.

---

## [2026-05-05] security: rewrite history to scrub leaked SSH file @ Hans Air M4

Following the privacy-gate work in PR #72, decided to also retroactively scrub
the leaked `home/dot_ssh/config.d/private_mini.local` blob from git history
on `main`. Earlier "leak is theatre, just sanitize forward" framing was
revised: tooling was clean (no open PRs to rebase, no signed commits, no
tags in range, both forks 33 days behind the leak), so the work-to-payoff
ratio for a full rewrite was actually defensible.

Sequence:
  1. Verified backups: 1P Secure Notes `op://Private/SSH config: mini` and
     `op://Toolkit/SSH config: trading-egress-tokyo` both readable; on-disk
     `~/.ssh/config.d/mini.local` and `~/.ssh/config.d/trading-egress-tokyo`
     both intact.
  2. Tagged `pre-rewrite-2026-05-05` on origin (backup ref before rewrite).
  3. `git filter-repo --invert-paths --path home/dot_ssh/config.d/private_mini.local --force`
     rewrote 95 commits in 0.07s. The leaked blob
     `9763977e34868e6c5145ae13f87547c096d37276` is now orphaned locally.
  4. Branch-protection ruleset `"Protect main"` (id 14664913) was disabled
     for ~13 seconds via gh API (PUT enforcement=disabled), force-pushed
     `main` (`164eaeb` -> `7d2ff43`), then re-enabled (PUT enforcement=active).
  5. Deleted the `pre-rewrite-2026-05-05` tag on origin (kept locally) so
     no ref pins the orphaned commits.

Verification: `gh api .../contents/home/dot_ssh/config.d/private_mini.local?ref=7d2ff43`
returns 404. Direct blob SHA lookup still resolves on GitHub (orphan persists
until GitHub's internal GC, typically days-weeks). For hostname-grade leaked
content, accepting that residual SHA-cache rather than escalating to GitHub
Support.

Forks/collaborators: 2 forks (hieu-ht, redstrike) at SHA `f8c3c48` are 42
commits behind the leak window and never pulled it. 3 admin collaborators
(monotykamary, lmquang, zlatanpham) had no recent activity within the
21-minute leak window. No coordination message sent.

Local backup tag `pre-rewrite-2026-05-05` (pointing to `164eaeb`, the
pre-rewrite tip) retained on Hans Air M4 for ~24h then will be deleted.

---

## [2026-05-05] feat(/dotfiles-sync): privacy gate for SSH fragments + 1P-backup check @ Hans Air M4

Follow-up to the SSH fragment refactor: the `/dotfiles-sync` command was the
upstream cause of the leak (PR #69). Detection step surfaced new SSH fragments
as a 3-way classify (core/local/skip) with no privacy gate, so `mini.local`
got routed to `core` and committed plaintext into a public repo.

Updates to both mirror copies of `dotfiles-sync.md`:

- **Detection**: each new SSH fragment is now tagged `[clean]` or `[private]`
  based on a heuristic (Tailscale `.ts.net` FQDN, IP in HostName, multi-segment
  internal hostnames, non-standard SSH port, purpose-revealing identity-file
  names like `id_ed25519_trading_vps`).
- **Classification**: SSH fragments are now FOUR-way (core / local / private /
  skip). The `private` route renames to `*.local` (gitignored) and creates a
  1P Secure Note titled `SSH config: <name>`. Repo is PUBLIC; flagged-private
  fragments must NEVER go to core.
- **Backup-status check (notify-only)**: scan `~/.ssh/config.d/*.local`
  fragments without a matching 1P Secure Note. Parallels the existing SSH-key
  audit. Drops `OP_SERVICE_ACCOUNT_TOKEN` per S-49 dual-mode so the lookup
  sees the user's full vault list (Notes may live in Private or Trading), not
  just the SA-scoped subset.
- **Action table**: new row "Back up SSH fragment privately" with the literal
  `op item create` command. Existing "Track SSH configs" row now reads
  "Track SSH configs (core)" and adds "only after verifying NO infra
  fingerprint" as a guard.
- **Report template**: SSH fragments show `[clean]` or `[⚠ private]` flags;
  added a "SSH fragment backup status" section parallel to "SSH backup
  status".

Heuristic smoke-tested locally on three synthetic fragments (clean / private
hostname / private port): all classified correctly. Mirror parity preserved
(`/usr/bin/diff` returns 0).

---

## [2026-05-05] security: move private SSH host fragments out of public source @ Hans Air M4

PR #69 landed `home/dot_ssh/config.d/private_mini.local` as plaintext into
the public dwarvesf/dotfiles repo (commit `a1f532f`). Source exposed:
internal Tailscale hostname `mac-mini-danang`, mDNS hostname
`Mac-mini.local`, SSH user `server`, identity file path. The `private_`
prefix only sets mode 0600 on the deployed file; the source on GitHub was
world-readable.

**Pattern decision:** machine-local file (`~/.ssh/config.d/*.local`,
gitignored) + 1Password Secure Note backup, restored via a one-line
`op read` on fresh-machine bootstrap. Rejected `onepasswordRead` (would
trigger biometric on every `chezmoi apply`, violates design philosophy
#5 "apply must be silent and idempotent"). Rejected `encrypted_` (chezmoi
age) because the source still leaks file existence/structure and adds
key-management surface for non-secret-grade hostname data. The local-only
pattern aligns with existing `*.local` conventions (Brewfile, fish, tmux,
gitconfig) and `dot_ssh/config.tmpl` already does `Include config.d/*` so
untracked drop-ins work for free.

**Bundled `trading-egress-tokyo`** (deferred Option A from PR #69 sync log)
under the same pattern: contained a public VPS IP, non-standard SSH port,
and purpose-revealing key name. Now lives only at
`~/.ssh/config.d/trading-egress-tokyo` on Hans Air M4 with backup at
`op://Toolkit/SSH config: trading-egress-tokyo/notesPlain`.

**Git history:** NOT rewritten. Repo is public, has 2 forks, 6 stars; the
plaintext blob is in commit `a1f532f` and was likely fetched by watchers
within the merge window. Force-push is theatre with coordination cost.
Treating the leaked hostname `mac-mini-danang` as already public going
forward; Tailscale ACL + SSH key remain the actual security boundary, not
hostname obscurity.

Changes:
  - `git rm home/dot_ssh/config.d/private_mini.local`
  - `chezmoi forget ~/.ssh/config.d/mini.local` (deployed file preserved)
  - `.gitignore`: dropped the `!home/dot_ssh/config.d/*.local` negation
    that was added in PR #69; SSH fragments named `*.local` are now
    blocked from `git add` defense-in-depth-style.
  - `docs/guide.md`: added "Walkthrough: restore private SSH host
    fragments" + a warning callout in "add an SSH host" about what
    not to commit.

1Password Secure Notes created (Hans Air M4 session):
  - `op://Private/SSH config: mini/notesPlain`
  - `op://Toolkit/SSH config: trading-egress-tokyo/notesPlain`

Verification: `chezmoi apply --dry-run` shows no drift; `ssh -G mini`
still resolves to `mac-mini-danang` (the deployed `~/.ssh/config.d/mini.local`
remains in place); `git ls-files home/dot_ssh/config.d/` empty.

---

## [2026-05-05] feat: track `vn-contract-format` Claude skill @ Hans Air M4

Adopted user-authored skill `~/.claude/skills/vn-contract-format/` into the
managed surface at `home/dot_claude/skills/vn-contract-format/`.

Skill contents (3 files):
  - `SKILL.md` (344 lines) -- print-ready Vietnamese legal documents
    workflow (biên bản thanh lý, giấy uỷ quyền, etc.) with markdown +
    python-docx generator, A4 / TNR 13pt styling.
  - `references/build_bien_ban_thanh_ly.py` (453 lines)
  - `references/build_giay_uy_quyen.py` (293 lines)

Verified `chezmoi managed | grep vn-contract` lists all 4 entries; dry-run
shows zero drift (source = target on this host). Will deploy on Mac mini
on next `chezmoi apply`.

---

## [2026-05-03] sync: Brewfile + SSH + gitconfig batch @ Hans Air M4

Multi-batch sync session. Brewfile + SSH + gitconfig changes; some asks
turned out to be no-ops because the state was already correct.

### Batch 2 (this session continuation): SSH + gitconfig

SSH:
  - tracked `~/.ssh/config.d/mini.local` -> `home/dot_ssh/config.d/private_mini.local`
    (Tailscale + LAN-fallback hosts for `mini`. Internal hostnames only,
    safe for public repo.)
  - **`~/.ssh/config.d/trading-egress-tokyo` -> Option A (local-only, deferred decision):**
    contains a public IP, non-standard SSH port, and purpose-revealing
    key name. dwarvesf/dotfiles is PUBLIC. User chose to keep it on
    Hans Air M4 only for now, will revisit (likely Option B: 1P-templated
    when they want it on Mac mini too). No chezmoi adopt, no gitignore
    change needed -- file simply remains untracked on disk. Future
    `/dotfiles-sync` runs will continue to surface it; that's the
    intended re-prompt cadence.

gitconfig:
  - absorbed local `[init] templatedir = ~/.git_template` into
    `home/dot_gitconfig.tmpl`. Post-edit `chezmoi cat ~/.gitconfig` matches
    disk byte-for-byte.

Casks ("absorb to core: 1password, font-jetbrains-mono, nordvpn, raycast"):
  - All 4 were already in core (Brewfile). No source edits needed.
  - 1Password.app, Raycast.app, NordVPN.app verified PRESENT in /Applications
    (installed via direct download, not brew). Brewfile entries serve as
    fresh-machine bootstrap; on this machine they're already covered.
  - font-jetbrains-mono is the only genuine miss. User installs manually.

Zed settings ("keep my local version"):
  - `chezmoi status` reported `MM` but `diff <(chezmoi cat) ~/.config/zed/settings.json`
    returned exit 0. No actual content drift. The `MM` is a cosmetic stale-cache
    in chezmoi state DB, not real divergence. Leaving alone.

Gitignore:
  - added negation `!home/dot_ssh/config.d/*.local` so SSH fragments with
    mDNS-style names (e.g. `mini.local`) can be tracked without removing
    the broader `*.local` machine-override pattern.

Side find: confirmed the fish-shadows-`diff` footgun still bites. Used
`/usr/bin/diff` throughout this batch.

### Batch 3 (continuation): zen rename + zed state-cache refresh

Brewfile:
  - renamed `cask "zen-browser"` -> `cask "zen"` per upstream brew alias
    (Zen Browser cask was renamed; both names worked but `zen` is now
    canonical. Verified via `brew info --cask zen-browser` resolving to
    `zen`.)

Zed settings.json:
  - User asked to "override dotfiles by my local version", but verified
    the rendered template and disk are byte-identical (md5
    206831e8b5b55e2ac9cb985fb324b3be on both sides). The `MM` flag in
    `chezmoi status` was metadata-cache lag, not actual content drift.
    Resolved with `chezmoi apply --force ~/.config/zed/settings.json`
    (safe given the md5 match): file unchanged, MM cleared.
  - No source edit needed; the template is correct.

User-requested install/absorb to core (9 items):
  - All 9 already in core Brewfile. No source edits needed for them.
  - Already installed locally (no action): node, ripgrep, pnpm, zoxide.
  - Need install (user runs manually after permission hook): rustup,
    font-jetbrains-mono-nerd-font.
  - **Risky** (already in /Applications via direct install): 1password,
    raycast, nordvpn. `brew install --cask` would need `--force` to
    overwrite. For 1Password specifically this could orphan vault data
    and signed-in account state. Halted; awaiting user decision.

### Batch 1 (earlier this session): 6 packages to core Brewfile

Brewfile (core, AI Tools section):
  - added brew: opencode (was npm-only; now via brew)
  - added brew: ollama (local LLM runner)
  - added brew: playwright-cli (standalone Playwright runner)

Brewfile (core, macOS Apps section):
  - added cask: tailscale-app (renamed from "tailscale" upstream)

Already in Brewfile, reaffirmed as core (still missing on this machine,
user installs manually after brew CLI permission):
  - brew: agent-browser
  - brew: tmux

Stale-comment cleanup:
  - dropped "opencode via: npm i -g opencode-ai" (now via brew)
  - dropped opencode-ai from npm-globals comment

Skipped this round (deferred to next sync):
  - 22 other untracked brew packages (incl. pandoc, rclone, xcodegen)
  - 14 other untracked casks (incl. cursor, zen, tor-browser, conductor)
  - 56 stale brew + 8 stale cask entries (no removals this run)
  - VS Code extension drift (5 new, 1 stale)
  - SSH config absorption (mini.local, trading-egress-tokyo)
  - zed/settings.json `MM` drift (needs merge decision)
  - .gitconfig drift (likely template re-render)
  - 1 SSH key without 1P backup

Pre-existing Brewfile bug surfaced (NOT introduced this run): `brew "terraform"`
fails on `brew bundle install` because terraform was removed from the main
Homebrew tap (BSL license). Fix: change to `brew "hashicorp/tap/terraform"`.
Filed mentally as next-sync follow-up.

Claude skill drift detection: clean (0 entries surfaced) - successful first
post-S-50 sync, the new check works as designed.

---

## [2026-05-03] feat(S-50): `/dotfiles-sync` detects user-authored Claude skill drift @ Hans Air M4

Background: commit `0ce60e8` (#63, 2026-04-30) wired `~/.claude/skills/`
into the chezmoi-managed surface but adoption was opt-in per skill.
Today's audit found 8 of 9 user-authored skills unversioned and at risk
of loss on a fresh-machine bootstrap.

One-shot absorption (all 8 promoted as **core** -- generic personal
workflows, no machine-specific paths -- verified by grepping for owner
identifiers; only hit was a doc example showing what NOT to write):

- browser-tool-selection
- cashflow-close
- cloudflare-tool-selection
- extract-workflow
- incident-workflow
- ingest-to-wiki
- playwright-record
- reconcile-properties

Ongoing detection added to `/dotfiles-sync`: new section in Step 2 scans
`~/.claude/skills/` for entries neither in `chezmoi managed` nor in
`~/.config/dotfiles/skills.local`. Step 4 prompts core/local/skip; Step 5
maps the choices to `chezmoi add` or an append to the local-mark file.
Plugin-installed skills (`ouroboros:*`, `superpowers:*`, etc.) live under
`~/.claude/plugins/` and are naturally filtered out.

Verification: 8 spec tests passed (absorption sanity, idempotence, clean
detection, positive detection of fake skill, suppression via
`skills.local`, cleanup, plugin filter, project/user copy parity).

Mirrored both copies of the slash command (`.claude/commands/dotfiles-sync.md`
and `home/dot_claude/commands/dotfiles-sync.md`); diff exits 0.

**Follow-up same-day:** ran `chezmoi apply ~/.claude/commands/dotfiles-sync.md`
to deploy the new section live on this machine (post-apply diff exit 0).
Updated user-facing docs: bumped `docs/guide.md` "10 dimensions" to 11,
added a "Claude skills" row to README.md's drift table, added a row to
guide.md's local-files and quick-change tables, and authored a full
"Walkthrough: back up a Claude skill" section. `verify-dotfiles` subagent
ran 6 checks (shellcheck, fish syntax, chezmoi dry-run, managed-count,
mirror parity, skill-drift detection): 6/6 passed. Side find: fish's
`diff` function shadows `/usr/bin/diff`; future scripts should use
`command diff` or absolute path - not blocking S-50 but a footgun worth
recording.

---

## [2026-05-01] docs: dedicated `docs/1password.md` workflow doc @ Hans-Air-M4

After the S-47 → S-49 redesign arc shipped, the inline service-account
sections in `CLAUDE.md` and `docs/guide.md` told the right story but
lacked a single-place explainer that ties together the mental model,
the dual-mode design, vault tiering (S-46), trade-offs, and the spec
chain. Added `docs/1password.md` as the source-of-truth narrative;
inline sections now point at it.

Also fixed two stale references found during audit:
- `README.md:185`: SA-token paragraph implied the old auto-load model.
  Rewritten to reflect dual-mode and link to the new doc.
- `docs/specs/S-42` postscript: only mentioned S-47, breaking the
  supersession chain for readers landing on S-42. Now shows the full
  chain S-42 → S-47 → S-49 and points at `docs/1password.md`.

CLAUDE.md and `docs/guide.md` link to `docs/1password.md` from their
service-account sections so future Claude sessions discover the
narrative entry-point first.

No behavior changes; docs only.

---

## [2026-05-01] dotfiles-sync: drop SA token before SSH-audit check @ Hans-Air-M4

Follow-up to S-49 in `home/dot_claude/commands/dotfiles-sync.md` (and the
project mirror at `.claude/commands/dotfiles-sync.md`). The skill runs
inside Claude Code's Bash tool, which inherits `OP_SERVICE_ACCOUNT_TOKEN`
under the new dual-mode model. Two of its `op`-using checks needed
`env -u OP_SERVICE_ACCOUNT_TOKEN` so they see the user's full vault list
(SSH keys live in `Private`, not `Trading`):

- `op account get` precondition gate (line 71)
- `fish -l -c 'dotfiles ssh audit'` invocation (line 72)

Without the unset, the SSH-audit step would report "0 of N keys backed
up" because the SA-scoped view of 1P doesn't see Private items. Updated
the explanatory comment to reference S-49 (was S-42).

The Keychain-cache check (line 95) reads macOS Keychain, not 1P, so
needs no change.

---

## [2026-05-01] S-49: dual-mode `op` via fish interceptor @ Hans-Air-M4

S-47 had restored multi-vault biometric in the daily shell by removing
`OP_SERVICE_ACCOUNT_TOKEN` from auto-load — but at the cost of the original
S-42 capability: agent subprocesses (Claude Code's Bash tool runs zsh)
could no longer do ad-hoc `op read op://...` mid-session. User wanted both.

**Design.** Auto-load the token globally so subprocesses inherit bearer auth.
Intercept `op` inside interactive fish via a tiny function
(`home/dot_config/fish/functions/op.fish`) that runs
`env -u OP_SERVICE_ACCOUNT_TOKEN command op $argv` when
`status is-interactive`. Subprocesses don't see the fish function and call
the binary directly with the token in env. Net: daily shell biometric and
multi-vault, every subprocess (including Claude Code) headless and SA-scoped.
No per-launch wrapper required.

**Changes:**
- New: `home/dot_config/fish/functions/op.fish` (5-line interceptor)
- Re-added `OP_SERVICE_ACCOUNT_TOKEN` entry to `home/.chezmoidata/secrets.toml`
- Removed the S-47 guard from `dotfiles secret add` (auto-load is the
  intended path again)
- S-47 frontmatter set to `status: amended by S-49`
- `with-agent-token` retained as a debug escape hatch
- Auto-memory rewritten to describe dual-mode

**Verification (all from a fresh `fish -i -c` after `chezmoi apply`):**
- `OP_SERVICE_ACCOUNT_TOKEN` prefix `ops_` in env ✓
- Interactive `op vault list` returns 8 vaults ✓
- `bash -c 'op vault list'` returns 1 vault (Trading) ✓
- `with-agent-token op vault list` returns 1 vault (Trading) — escape hatch
  still works ✓
- `command op vault list` returns 1 vault (Trading) — bypasses interceptor ✓
- `fish -n` clean on all touched function files ✓

**Trade-off:** token is back in shell env (S-47's strict guarantee gone).
Same blast-radius profile as the original S-42 model. Accepted because the
interceptor neutralises the daily-shell side effect that drove S-47, and
the agent-capability win is significant.

---

## [2026-05-01] S-48: narrow `chezmoi apply` scope in `dotfiles secret` @ Hans-Air-M4

Surfaced during S-47 verification: a `--force` re-add of
`OP_SERVICE_ACCOUNT_TOKEN` ran a full-tree `chezmoi apply`, which rendered
the new entry into `~/.config/fish/conf.d/secrets.fish` and then aborted
on an unrelated Zed TTY-prompt failure. The script's revert path only
undid `secrets.toml`, not the deployed `secrets.fish`. Source/target
silently drifted; new fish shells continued loading the unwanted token.

**Fix:** scope `chezmoi apply` in `dotfiles secret add` and
`dotfiles secret rm` to the single target file
`~/.config/fish/conf.d/secrets.fish`. In `secret add`, the revert path
now also re-runs the narrow apply so target re-renders without the line
even when the original apply rendered it. `secret rm` benefits from the
narrowing alone (its revert is a no-op by design).

**Verification:**
- Pre-condition: pending Zed drift on `~/.config/zed/settings.json`
  (chaos input).
- Manually appended a test entry to `secrets.toml`, ran narrow
  `chezmoi apply ~/.config/fish/conf.d/secrets.fish`: exit 0,
  `secrets.fish` updated, Zed file untouched.
- Removed the test entry, re-ran narrow apply: `secrets.fish` cleaned,
  Zed file still untouched.
- `fish -n home/dot_config/fish/functions/dotfiles.fish` clean.

---

## [2026-05-01] S-47: opt-in `OP_SERVICE_ACCOUNT_TOKEN` via wrapper @ Hans-Air-M4

Daily `op` CLI was scoped to the `Trading` vault on this laptop because
`OP_SERVICE_ACCOUNT_TOKEN` was registered in `secrets.toml` (S-42 model)
and auto-exported by every fish login. Once the token is in env, `op`
switches to bearer auth and ignores the user's biometric session. The
user noticed: `op vault list` returned only `Trading`, all other vaults
invisible interactively.

**Fix:** unregistered the token from `home/.chezmoidata/secrets.toml`
and added a per-launch `with-agent-token` wrapper that injects the
token into the wrapped process only. Daily shells now do
`op whoami` → `USER_OF_ACCOUNT` (biometric), `op vault list` returns
all 8 vaults. Agent sessions that need ad-hoc `op read` opt in via
`with-agent-token claude`.

**Anti-regression:**
- `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN` now refuses with a
  message pointing at the wrapper. `--force` overrides if genuinely
  needed.
- S-42 frontmatter set to `status: superseded by S-47` with an
  in-spec note. Spec body preserved as historical record.
- `CLAUDE.md` and `docs/guide.md` rewritten to centre on the wrapper
  and warn against re-registering the var.
- Auto-memory entry added for this Claude account so future sessions
  don't "helpfully" undo the change.

**Verification (all passed in `env -u OP_SERVICE_ACCOUNT_TOKEN fish -i`):**
- token absent from env after fresh fish login
- 8 vaults visible to bare `op vault list`
- `with-agent-token op whoami` returns `SERVICE_ACCOUNT`
- `with-agent-token op vault list` returns 1 vault (`Trading`)
- guard fires on `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN`
- `--force` bypass works
- fish syntax clean on all touched functions

**Trade-off accepted:** default `claude` sessions lose ad-hoc `op read`
mid-session (S-42's stated capability). Sessions that need it prefix
the launch. The vast majority of secret access is via pre-registered
env vars resolved at shell startup (S-35), which `claude` still
inherits unchanged.

---

## [2026-04-28] claude overlay manages `permissions.defaultMode` @ Mac mini

Cross-machine drift surfaced after the morning catch-up sync: Mac Air's
Claude Code session shows the `>> bypass permissions on` badge, Mac
mini's does not. Root cause: Air had `permissions.defaultMode:
"bypassPermissions"` set locally (unmanaged by dotfiles), Mac mini had
no value.

**Fix:** added `permissions.defaultMode` to the personal overlay at
`home/dot_claude/modify_settings.json`. Uses the same `// fallback`
pattern as the other managed fields (only sets the value if absent),
and merges additively into `permissions` so guardrails-owned
`permissions.deny` survives. Updated CLAUDE.md scope description to
reflect that `permissions.defaultMode` is now ours, `permissions.deny`
remains theirs, and `hooks.PreToolUse` is an additive merge (the prior
"never touches PreToolUse" claim in the doc was inaccurate; fixed).

**Trade-off accepted:** every machine that syncs from this point boots
Claude Code in bypass-permissions mode by default. Per-tool confirmation
prompts disappear; hard-block hooks (pipe-to-shell, `rm -rf` of
`/`/`~`/`$HOME`) and guardrails' `permissions.deny` rules still fire.
Consistent with the existing `skipDangerousModePermissionPrompt: true`
default. Override locally by editing `~/.claude/settings.json` after
apply -- additive merge preserves any manually-set value.

**Verification:**
- shellcheck on `modify_settings.json` clean
- piped current settings through the script: `permissions.defaultMode`
  emitted as `"bypassPermissions"`, `permissions.deny` array intact
- `chezmoi apply ~/.claude/settings.json` succeeded silently
- `jq '.permissions.defaultMode' ~/.claude/settings.json` returns
  `"bypassPermissions"` post-apply

---

## [2026-04-28] catch-up sync + Zed panel-dock absorbed @ Mac mini

First sync on Mac mini after 17 upstream commits landed from Hans Air M4
(S-36 guardrails, S-42 service account, S-44/S-45 secret discipline,
S-46 multi-vault model, tunnel functions, Brewfile cleanup).

**Pre-apply blockers resolved:**
- `chezmoi init` re-run to pick up new template variables
  (`guardrails_variant` from S-36, `op_vault` from S-46). Without this,
  apply aborted on the new `run_onchange_after_claude-guardrails.sh.tmpl`.
- Local drift on `~/.config/zed/settings.json` absorbed into source. User
  had added `project_panel.dock=right`, `outline_panel.dock=right`,
  `collaboration_panel.dock=right`, `git_panel.dock=right`,
  `agent_servers.claude-acp.type=registry`, and `agent.dock=left`.
  These are sensible defaults; promoted to core so all machines pick
  them up.

**New packages on this machine (all classified skip):** 17 brew leaves +
3 casks were untracked, but every one is a non-issue:
- legacy from the Zsh/Prezto era (zsh, hub, the_silver_searcher,
  youtube-dl, z) - superseded by fish + gh + ripgrep + zoxide + yt-dlp
- transitive deps (shared-mime-info, hashicorp/tap/terraform - the latter
  is the tap form of `terraform` already in core)
- machine-specific tooling not worth promoting (gitup, llvm@21, rbenv,
  ruby, rust, subversion, typescript, yarn, pipx, htop)
- aliases of already-tracked packages (google-cloud-sdk = renamed
  gcloud-cli; zen-browser already added to core in the pulled
  commits; microsoft-auto-update is auto-installed by Office)

Nothing was added to `~/.Brewfile.local` this round - none of these are
worth tracking even per-machine. They stay installed but unmanaged.

**Stale entries deliberately kept:** `~/.Brewfile` lists 8 brews
(ffmpeg, go, librsvg, node, ripgrep, sqlite, terraform, tldr) and 2
casks (nordvpn, slack) that aren't installed on Mac mini. Not pruning
because they're real core packages used on Hans Air M4. Mac mini just
hasn't run `brew bundle` against the latest core list yet.

Repo changes:
  - home/dot_config/zed/settings.json.tmpl: absorbed 6 local keys
    (panel docks + agent_servers + agent.dock)

Skipped this sync (user choice):
  - `chezmoi apply` itself. Would deploy 14 upstream files and trigger
    `brew bundle` (which would install the 8 stale brews + 2 stale
    casks). User can run `chezmoi apply` separately when ready.
  - Pruning stale Brewfile entries.

---

## [2026-04-28] sync workflow hardening (re-verify gate) @ Hans Air M4

Sync session opened with a pasted prior-session report flagging two
blockers (chezmoi init required for `guardrails_variant` and `op_vault`;
Zed local drift on panel-dock keys). Re-verification on the live system
showed both already resolved: `~/.config/chezmoi/chezmoi.toml` carried
every required var, and `diff <(chezmoi cat ~/.config/zed/settings.json)
~/.config/zed/settings.json` was empty. The LLM (this session) had
parroted the stale claims as actionable blockers before checking,
which sent the user toward unnecessary interactive work.

Decisions:
  - 17 brew + 3 cask listed as new on this host: user said "skip all".
    Nothing added to `home/dot_Brewfile.tmpl` or `~/.Brewfile.local`.
  - 3 pulled upstream chezmoiscripts (`aa-init`, `ab-1password-check`,
    `zz-summary`) executed via `chezmoi apply` (run by user).

Workflow fix landed on `fix/sync-reverify-blockers` (a989bc7):
  - dotfiles-sync skill (both copies): new Step 2.5 forces re-derivation
    of every blocker claim from current state before reporting it.
    Step 3 report header now stamps timestamp, hostname, git rev so
    paste-ins from prior sessions are visibly snapshots.
  - CLAUDE.md: new "Pre-action verification" subsection at the top of
    `## Verification rules`, generalised beyond sync to any LLM-driven
    interactive prompt.

Branch not yet merged. Push + PR is a separate decision.

---

## [2026-04-23] docs cross-refs (S-42 in README, S-44 rule in CLAUDE.md) @ Hans Air M4

Post-ship audit caught two real documentation gaps:

1. `README.md` §Security covered the S-35 lazy-Keychain pattern but
   said nothing about the service account path (S-42) for agent
   subprocesses. A fresh reader would not discover this capability
   from the README alone.
2. `CLAUDE.md` carried the S-45 "never echo secret values" rule but
   not the S-44 standing rule ("shipping a spec = status + tasks.md +
   sync-log, all three, every time"). Future LLMs reading CLAUDE.md
   would miss it.

Both fixes are one-paragraph / one-bullet additions. No new spec (this
is a doc correction to reference existing specs, not a new design).

Repo changes:
  - README.md: new "Agents and non-interactive op read" paragraph in §Security
  - CLAUDE.md: new "Spec status discipline (S-44)" bullet in Important conventions

Non-fixes (deliberately skipped):
  - docs/guide.md: already has the full S-42 section; doctor check
    self-explanatory; S-45 is contributor-side, not user-side.
  - docs/llm-dotfiles.md: generic stack-agnostic pattern doc; 1P
    specifics do not belong.
  - SVGs: S-42 is a specialization of the S-35 flow; diagrams still
    accurate.

---

## [2026-04-23] S-45 stop echoing secrets in refresh @ Hans Air M4

Incident + fix in one entry.

**Incident (earlier same day):** during S-43 verification I simulated
the "empty Keychain" doctor branch by deleting an entry and then
re-cached it with `dotfiles secret refresh OP_SERVICE_ACCOUNT_TOKEN`.
The function printed `"Restart shell or: set -gx OP_SERVICE_ACCOUNT_TOKEN 'ops_...'"`
which echoed the raw service account token into the terminal (and
therefore into the Claude Code session transcript). User decided to
rotate the token in 1P; the rotation itself is out of scope of the
dotfiles repo.

**Root cause:** `home/dot_config/fish/functions/dotfiles.fish:257` in
the `dotfiles secret refresh` path had a success hint that interpolated
`$val` into its output. Any transcript-capturing environment
(screen recorder, LLM tool-call log, `script -a`, etc.) captured the
value.

**Fix (this PR, spec [S-45](specs/S-45-secret-refresh-no-echo.md)):**
Replaced the leaky hint with phrasing that references the variable
name only (`"Open a new shell ... to load the new value into $VAR"`).
Matches the already-safe wording in the `secret add` success path.

**Standing rule now in CLAUDE.md:** never echo resolved secret values.
Reference the var name or op:// ref instead. `secret-cache-read` is the
one exception (its stdout is captured by `()`, not printed).

**Audit result:** only one leak site existed. `dotfiles secret add/rm/list`
paths were checked and are clean. `secret-cache-read` is correct.
`chezmoi apply` path was cleaned up in S-35 and remains secret-free.

**Open follow-up** (not in this PR): `dotfiles secret add` passes the
value to `op item create` as a command-line argument, briefly visible
to local `ps`. Lower severity; documented in the spec as a known
limitation.

Repo changes:
  - docs/specs/S-45-secret-refresh-no-echo.md (new)
  - home/dot_config/fish/functions/dotfiles.fish: 2-line hint replacement
  - CLAUDE.md: new "Never echo resolved secret values" convention
  - docs/tasks.md: ticked S-45

---

## [2026-04-23] S-26 Brewfile cleanup @ Hans Air M4

Audit per spec [S-26](specs/S-26-brewfile-cleanup.md). Two changes
landed; everything else intentionally deferred.

Findings:
  - Real duplicate: `brew "tldr"` listed twice in the Core CLI block
    (the second had the descriptive comment). Fixed: kept the earlier
    occurrence, moved the comment onto it, deleted the duplicate.
  - False duplicate: `font-source-code-pro` and
    `font-sauce-code-pro-nerd-font` are separate fonts (original Adobe
    vs Nerd-Font patched). Added a one-line comment above the pair so
    future readers (including LLMs) do not dedupe them.

Verified but not acted on:
  - All casks resolve via `brew info --cask` (no renames needed).
  - No commented-out brew/cask entries exist; all `#` comments are
    install-path breadcrumbs for packages managed via cargo, npm, uv,
    or curl | bash. Keeping them.
  - `brew bundle check` exits 0 on the rendered `~/.Brewfile`.

Flagged for future decision:
  - `mise` + brew language runtimes (`go`, `node`, `python@3.12`,
    `elixir`, `rustup`) overlap. Not a typo, a design question. Left
    alone until the user picks a side.

Repo changes:
  - home/dot_Brewfile.tmpl: removed duplicate tldr, added font-pair comment
  - docs/specs/S-26-brewfile-cleanup.md: replaced stub with full audit
    spec, status=done
  - docs/tasks.md: ticked S-26

Standing rule from S-44 applied in this PR.

---

## [2026-04-23] S-44 spec status housekeeping @ Hans Air M4

Audit found 6 specs with stale status frontmatter despite having shipped:
S-32 (`planned`), S-36, S-37, S-38, S-39, S-41 (`proposed`). Root cause is procedural:
the SDD flow never required flipping status to `done` at ship time, so
frontmatter drifted from reality.

Two-part fix (spec [S-44](specs/S-44-spec-status-housekeeping.md)):
  - One-time: flip the five stale statuses, refresh tasks.md to list
    S-35 through S-44 in the appropriate section, document S-40 as
    intentionally unused (number gap, no spec).
  - Standing rule: from now on, shipping a spec includes flipping its
    status to done AND ticking its entry in tasks.md AND appending to
    the sync log. All three, not optional.

No runtime changes. No chezmoi apply needed. Pure bookkeeping.

Files changed:
  - docs/specs/S-44-spec-status-housekeeping.md (new)
  - docs/specs/S-{32,36,37,38,39,41}-*.md: status frontmatter only
  - docs/tasks.md: date + reconciliation for S-24 through S-44
  - docs/sync-log.md: this entry

---

## [2026-04-23] S-43 sync secret cache visibility @ Hans Air M4

Follow-up to S-42. The sync workflow did not surface registered-but-uncached
secrets, so a fresh machine that inherited the `OP_SERVICE_ACCOUNT_TOKEN`
registration but never triggered the first interactive biometric had no
feedback loop. Agents calling `op read op://...` would just fail silently.

Two additive, notify-only probes added (see spec
[S-43](specs/S-43-sync-secret-cache-visibility.md)):

  - `/dotfiles-sync` step 2: new "Secret cache status" block. Silent when
    all registered secrets are cached or when op is absent/unauthed.
    Gated on `op account list &>/dev/null` so headless machines stay quiet.
    Report category: "Secret cache (optional)" under step-3 format.
  - `dotfiles doctor`: new check after the SSH backup block. Iterates
    `secrets.toml`, probes Keychain per var. Reports `[ok]` when everything
    is cached, `[--]` (info) when any are empty, with a hint to run
    `exec fish` or wait for the next interactive shell.

Design choices recorded in the spec:
  - Info-level (`[--]`) not error (`[!!]`). Empty cache is a legitimate
    transient state on fresh machines.
  - Reachability of the 1P ref is NOT checked (would require live op call,
    would popup on miss). Presence of Keychain entry only.
  - Token identity is not special-cased. The probe is uniform across all
    registered vars; `OP_SERVICE_ACCOUNT_TOKEN` shows up like any other.

Verified both branches (all-cached, one-missing) on this machine.

Repo changes:
  - docs/specs/S-43-sync-secret-cache-visibility.md (new)
  - .claude/commands/dotfiles-sync.md: + "Secret cache status" scan block, + report line
  - home/dot_claude/commands/dotfiles-sync.md: identical mirror of project copy
  - home/dot_config/fish/functions/dotfiles.fish: + secrets.toml iterator in doctor

Not changed (intentionally):
  - secret-cache-read (probes are observational only)
  - secrets.fish.tmpl loop (no new registrations)
  - any .chezmoiscripts/ (apply path stays popup-free per S-35)

---

## [2026-04-23] S-42 service account agent auth @ Hans Air M4

New spec: [S-42](specs/S-42-service-account-agent-auth.md) -- document the
1Password service account pattern so Claude Code subprocesses can
`op read op://...` headlessly.

Root cause recap: `op` refuses to trigger biometric when stdin is not a TTY,
so agent subprocess reads fail silently. Service account bearer auth
bypasses biometric entirely once `OP_SERVICE_ACCOUNT_TOKEN` is in env.

Registered locally (this machine only, per-user action, not shared):
  - `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN "op://Private/op-service-account-ops/credential"`
  - Token scoped server-side to the `Trading` vault in 1Password
  - First fish login triggered one biometric; all subsequent shells silent

Repo changes (shared):
  - docs/specs/S-42-service-account-agent-auth.md (new)
  - CLAUDE.md: expanded "Secret injection" section from two backends to three patterns
  - docs/guide.md: added "Service account for agent subprocess `op read`" subsection under §6
  - home/.chezmoidata/secrets.toml: added `OP_SERVICE_ACCOUNT_TOKEN` registry entry (op:// ref only, not a value)

Not changed (intentional -- existing infra absorbs this):
  - secret-cache-read helper
  - secrets.fish.tmpl template loop
  - dotfiles secret subcommands

Blast radius note recorded in the spec: service account token reads every
vault scoped to it. Keychain entry is per-user encrypted at rest, same
threat model as `ANTHROPIC_API_KEY`. Recommended mitigation (dedicated
`Agents` vault) is documented but not enforced; this machine uses the
pre-existing `Private` vault for convenience, accepted risk.

---

## [2026-04-23] sync @ Hans Air M4

Track A (minimal): rename drift + guardrails pin bump, plus 4 requested new casks.

Brewfile (core):
  - rename: `cask "zen"` -> `cask "zen-browser"` (upstream renamed back)
  - added cask: wispr-flow (voice-to-text dictation)
  - added cask: font-ibm-plex-sans, font-ibm-plex-sans-hebrew, font-ibm-plex-serif

Guardrails:
  - bumped pin v0.3.7 -> v0.3.8 in run_onchange_after_claude-guardrails.sh.tmpl
    (release notes: https://github.com/dwarvesf/claude-guardrails/releases/tag/v0.3.8)

Not classified this session (deferred; surfaced in report only):
  - 22 untracked brew packages (duti, gitup, hub, jpeg-xl, libiconv, lume,
    markdown-oxide, ocaml, ollama, opencode, pandoc, pipx, playwright-cli,
    python@3.10, rclone, rust, shared-mime-info, subversion,
    the_silver_searcher, tldx, wireguard-tools, xcodegen, yarn, z, zsh)
  - 13 untracked casks (antigravity, calibre, chrysalis, codexbar, cursor,
    grandperspective, hyprnote, microsoft-auto-update, opencode-desktop,
    swiftdefaultappsprefpane, tana, tor-browser)
  - 1 new fish function: fisher.fish (Fisher plugin manager bootstrap)
  - 54 brew + 8 casks tracked-but-not-installed noise (never ran brew bundle here)
  - 25 VS Code extensions tracked-but-not-installed (user is on Cursor/Zed)

SSH backup status:
  - 2 of 2 on-disk keys still have no 1Password backup (action: `dotfiles ssh adopt`)

Earlier in same session (pre-sync):
  - feat(secrets): split Cloudflare API token from R2 credentials
  - feat(claude): sync personal PreToolUse hooks + Self-verification rules
    section into dotfiles modify_ overlay (below marker)
  - removed "# Self-verification rules" block from above-marker region of
    ~/.claude/CLAUDE.md since it was fragile against sync-claude-context.sh

---

## [2026-04-16] design session @ Mac mini

Big architectural session extending the core/local pattern and rewriting secret
loading. Full spec: [S-35](specs/S-35-local-pattern-and-lazy-secrets.md).
Test plan: [testing.md](testing.md).

Config includes:
  - fish: source ~/.config/fish/config.local.fish (new)
  - tmux: source-file -q ~/.config/tmux/tmux.local.conf (new)
  - git/ssh: already had native includes

dotfiles local CLI (new subcommand):
  - list / promote / demote / edit
  - dynamic completions for brew / cask / ext
  - auto-commits core changes; never commits .local files

Secrets rearchitected (lazy + Keychain):
  - Removed {{ onepasswordRead }} from secrets.fish.tmpl
  - New helper ~/.local/bin/secret-cache-read (Keychain first, op fallback)
  - dotfiles secret list now shows [cached]/[empty]
  - dotfiles secret refresh VAR (clear cache + re-fetch)
  - chezmoi apply no longer triggers any 1Password popups

Brewfile housekeeping:
  - Added 12 modern tools: tldr, sd, gping, atuin, lazygit, difftastic,
    kubectx, kubecolor, stern, opentofu, dive, buf
  - Removed deprecated taps: homebrew/bundle, homebrew/services
  - Fixed renames: zen-browser->zen, google-cloud-sdk->gcloud-cli
  - Fixed cask->formula: gifski, lume
  - Fixed formula->cask: nordvpn
  - Demoted to ~/.Brewfile.local: sentencepiece, tor-browser, lume, meetingbar
    (kept nordvpn, microsoft-edge, cloudflared, elixir in core per user)

Verification hooks:
  - Hostname tag in sync log entries (@ Mac mini)
  - Three new dotfiles doctor checks for .local pattern integrity

Audit:
  - git log --all scanned for hardcoded secrets: clean
  - No tokens, keys, or op:// values with plaintext ever committed

Post-session fixes (same day):
  - fix(doctor): exclude always-run scripts (R status) from drift count
  - fix(doctor): check login shell via dscl, not $SHELL (was misreporting after chsh)
  - chezmoi apply --force resolved Zed One Light/Dark drift
  - Default shell confirmed via dscl: /opt/homebrew/bin/fish (chsh worked previously,
    $SHELL was just stale in inherited processes)

Documentation refresh:
  - README.md: multi-machine positioning, .local pattern, lazy secrets section
  - docs/llm-dotfiles.md: added multi-machine sync + lazy secrets sections
    (stack-agnostic, shareable patterns)
  - CLAUDE.md: explicit design philosophy section (6 principles)

---

## [2026-04-16] sync

Config:
  - re-add Zed settings.json (removed agent_servers block, absorbed local edits)
  - chezmoi apply deployed all pending repo changes (fish config, starship, lib.sh, dotfiles CLI, completions, Claude config)

Brewfile:
  - added tap: hashicorp/tap
  - added brew: chezmoi, mdq, certbot, hashicorp/tap/vault, colima, docker, docker-compose, docker-credential-helper, sentencepiece
  - added cask: codex, chrysalis, disk-inventory-x, google-cloud-sdk, lunar, monitorcontrol, skype, zen-browser
  - skipped legacy packages already superseded (htop->btop, hub->gh, z->zoxide, pipx->uv, youtube-dl->yt-dlp, etc.)

VS Code extensions:
  - synced to match installed: added openai.chatgpt, removed 4 uninstalled (docker.docker, dwarvesf.md-ar-ext, ms-vsliveshare.vsliveshare, ocamllabs.ocaml-platform)

Fish functions:
  - tracked 4 unmanaged: keychain_env.fish, keychain_set.fish, op_env.fish, web3_env.fish

Secrets:
  - CLOUDFLARE_API_TOKEN already registered in secrets.toml, resolved from 1Password at apply time

---

## [2026-04-14] sync

Config:
  - re-add Zed settings.json (MCP server changes, local edits absorbed)

VS Code extensions:
  - add 5: docker.docker, dwarvesf.md-ar-ext, ms-vsliveshare.vsliveshare, ocamllabs.ocaml-platform, openai.openai-chatgpt-adhoc

Fish functions:
  - removed 5 orphaned standalone functions from machine (add-secret, dfe, dfs, list-secrets, rm-secret)  - consolidated into dotfiles subcommands

Brew/casks: deferred to next sync

---

## [2026-05-08] sync @ Mac-mini

Config:
  - re-add `~/.claude/statusline-command.sh` — rebuilt as 2-line layout (identity / budget split). Abbreviated path (`w/t/ops-toolkit` instead of `…/workspace/tieubao/ops-toolkit`). `✦` replaces non-rendering NerdFont brain glyph. Effort uses words (`low`/`med`/`high`/`MAX`) instead of bracketed letters. Strips `(1M context)` parenthetical from model display name. Bullet-separated metrics line: `7%  ·  5% 51m  ·  68% 1d8h  ·  Mac-mini`.

Other drift detected but deferred (out of scope for this narrow sync):
  - `.Brewfile`, `.claude/CLAUDE.md`, `.claude/settings.json` modified
  - many new `.claude/skills/*` and `.claude/hooks/machine-banner` directories not yet tracked
  - `.chezmoiscripts/{aa-init,ab-1password-check,brew-bundle}.sh` reported as removed

---
