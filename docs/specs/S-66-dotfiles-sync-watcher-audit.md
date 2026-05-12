---
id: S-66
title: /dotfiles-sync audits S-64 watcher health
type: feature
status: done
date: 2026-05-13
extends: S-64, S-65
---

# S-66: `/dotfiles-sync` audits S-64 watcher health

Extends [S-64](S-64-dotfiles-watch.md) (the continuous dotfiles watcher) and [S-65](S-65-dotfiles-watcher-doc-sweep.md) (the post-ship doc sweep) by adding the missing operational audit. Today, `/dotfiles-sync` *uses* the watcher (one paragraph note explaining empty Drift sections are the steady state) but does not *verify* the watcher is healthy. If the watcher is silently broken on a machine, the empty Drift section turns from "everything is absorbed" into "the absorber is dead and nothing surfaced it."

## Problem

`/dotfiles-sync` runs nine other notify-only audits today: secret cache status, SA token rotation, claude-guardrails upstream release, SSH backup status, hardcoded secrets in fish config, already-local overrides, etc. The S-64 watcher is the only first-class subsystem of the dotfiles workflow with **no** sync-time health check.

Concretely, today none of these five failure modes get surfaced during `/dotfiles-sync`:

1. **Either LaunchAgent stopped running.** `launchctl bootout` happened (manual or after a crash loop), `dotfiles watch install` was never re-run. The watcher silently does nothing.
2. **Plist out of sync with `chezmoi managed`.** New files got added to the source state, but the `run_onchange` wiring script did not re-fire (manual `chezmoi edit` paths, source-only adds, or a failed apply). New files are not in the WatchPaths array, so launchd never fires on them.
3. **Stale lock.** `~/Library/Caches/dotfiles-watcher.lock` left behind by a crashed tick. Subsequent ticks exit silently on `mkdir`-fails. Spec's 60s stale-lock forgiveness only kicks in inside a tick; an external lock older than 60s indicates something genuinely wrong.
4. **fswatch binary missing.** `brew bundle` was skipped, partial install, user demoted fswatch to `.Brewfile.local` on a different machine. The fswatch agent crash-loops via launchd KeepAlive; the WatchPaths agent silently covers the flat-file case but loses recursive coverage.
5. **Log gone cold.** No `TICK` entries in the watcher log for >7 days on a machine where the operator is actively editing managed files. Strong signal something is wrong (agent unloaded, tick script unexecutable, etc.) even if `launchctl print` claims the agent is loaded.

Today the operator only finds out by manually running `dotfiles watch status` or noticing drift accumulating in `git status` and wondering why. The whole point of `/dotfiles-sync` is to be the periodic "tell me what's wrong" sweep — leaving the watcher out is a real gap. Found in conversation 2026-05-13.

## Solution

Two pieces. Mirrors the S-43 / S-49 / S-63 pattern: a small CLI verb that emits machine-parseable status, plus a sync-skill section that calls it and surfaces findings.

### 1. New `dotfiles watch doctor` verb

Single-shot health check. POSIX exit codes (0 = healthy, non-zero = at least one issue). Prints one line per check using the existing `lib.sh` `info` / `warn` / `err` helpers so colors and the apply-log surface match the rest of the dotfiles UX.

Checks (each is one line of output, prefixed `[ok]` / `[warn]` / `[err]`):

| Check | Probe | Severity if failing |
|---|---|---|
| `agent-wp` | `launchctl print "gui/$UID/com.truonghan.dotfiles-watcher"` returns 0 and `state = running` | err |
| `agent-fs` | same for `com.truonghan.dotfiles-watcher-fswatch` | err |
| `plist-fresh` | sha256 of `chezmoi managed` matches the `managed-set fingerprint:` comment in the deployed `~/Library/LaunchAgents/com.truonghan.dotfiles-watcher.plist`. Mismatch means managed set drifted since last wiring | warn |
| `lock-stale` | `~/Library/Caches/dotfiles-watcher.lock` either absent or younger than 60s | warn |
| `fswatch-bin` | `command -v fswatch` resolves AND `fswatch --version` exits 0 (catches stale Homebrew install where the binary is in PATH but unusable after macOS upgrade) | err |
| `log-warm` | `~/Library/Logs/dotfiles-watcher.log` exists and mtime is within 30 days, OR file is empty (acceptable steady state on idle machines) | warn |

Each `[warn]` / `[err]` line includes a "Fix:" suffix with the exact command to re-mediate (`dotfiles watch install`, `brew bundle`, `rm -f <lock>`, etc.). Mirrors the existing `dotfiles doctor` style.

Headless-skip: if `chezmoi data | jq -r .headless` is `true`, doctor exits 0 with one `[ok] watcher: headless, skipped` line.

Implementation lives in `home/dot_local/bin/executable_dotfiles-watch-doctor` (POSIX sh, sourced by the fish `case doctor` branch). Pulling it out of fish lets the sync-skill markdown invoke it directly without going through a fish subshell.

`dotfiles watch` help text gains the `doctor` row. `dotfiles watch doctor` returns its own exit code; `dotfiles watch status` is unchanged (the existing two-line summary stays as the quick eyeball check).

### 2. New `/dotfiles-sync` audit section

In `home/dot_claude/commands/dotfiles-sync.md`, after the existing **Step 2 / Secret cache status** subsection and before **SA token rotation**, add:

```markdown
### Watcher health (notify-only)
```bash
# Run the dedicated audit. Each [warn]/[err] line includes its own fix
# suffix; we surface them verbatim. Headless boxes self-skip inside the
# script (one [ok] line). Silent on a fully healthy machine.
if command -v dotfiles >/dev/null 2>&1; then
    fish -l -c 'dotfiles watch doctor' 2>/dev/null \
      | grep -E '^\[(warn|err)\]' \
      || true
fi
```

The skill's existing **Note on the S-64 watcher** paragraph (S-65 § Step 2 framing) stays — it explains the empty Drift section. The new audit covers the inverse case ("Drift section is empty AND the watcher is broken"), so the two reinforce each other rather than duplicate.

Notify-only is deliberate: per [the S-64 design philosophy](S-64-dotfiles-watch.md), the LLM does bookkeeping, the user makes decisions. Auto-running `dotfiles watch install` from inside a sync would silently mask the drift-debugging signal.

### 3. Wiring + tests

- `home/.chezmoiscripts/run_onchange_after_dotfiles-watcher.sh.tmpl` already writes the `managed-set fingerprint:` sha256 comment into the plist. Confirm it's present (line 17 currently writes it into the *script* header, but the *plist*'s `<!-- managed-set fingerprint: ... -->` comment is what the doctor probes). Either move/duplicate the fingerprint into the plist itself, or have the doctor re-hash `chezmoi managed` and diff against a marker stored elsewhere (`.cache/dotfiles-watcher.managed.sha256`). Pick the lower-friction option during implementation; both work.
- New test cases in `tests/dotfiles-watch.sh` (existing suite is 17/17 after S-65; this adds 5-7 more):
    1. `doctor` exit code 0 on a synthesized clean state (fake `launchctl`, fingerprint match, no lock, fresh log).
    2. `doctor` exits non-zero and prints `[err] agent-wp` when fake `launchctl print` returns 1.
    3. `doctor` prints `[warn] plist-fresh` when the fingerprint differs.
    4. `doctor` prints `[warn] lock-stale` when the fake lock dir is >60s old.
    5. `doctor` prints `[err] fswatch-bin` when `command -v fswatch` fails inside a `PATH=` override.
    6. Headless mode (`chezmoi data | jq` shim returns `{"headless": true}`) → exits 0, one `[ok] watcher: headless` line.
    7. `shellcheck --severity=warning` on `executable_dotfiles-watch-doctor` clean.

The skill-side bash block is exercised by running `/dotfiles-sync` end-to-end on the Mac mini after install, and confirming the section appears empty when the watcher is healthy + appears with a `[warn]` line when one agent is bootout'd.

## Test (acceptance)

1. `bash tests/dotfiles-watch.sh` reports 22/22+ pass (existing 17 + new 5-7).
2. On the Mac mini (current state: both agents running per Q3 of the originating conversation): `dotfiles watch doctor` exits 0 with no `[warn]`/`[err]` lines, and `/dotfiles-sync` Step 2's Watcher Health subsection is silent.
3. Manually `launchctl bootout gui/$UID/com.truonghan.dotfiles-watcher-fswatch`, re-run `/dotfiles-sync`: the report's drift-and-audit section now contains the `[err] agent-fs — Fix: dotfiles watch install` line, exactly once, in the right report position per the S-54 visual layout.
4. `dotfiles watch install` restores health; subsequent `doctor` is clean.

## Out of scope

- **Auto-fix.** Doctor reports, never repairs. Same rationale as the watcher itself not auto-committing: silent self-healing erodes the operator's mental model of what state the machine is in. The fix suffix gives them a one-liner; they decide when to run it.
- **Per-tick correctness.** No attempt to verify "the watcher would have absorbed this specific file." That's what `tests/dotfiles-watch.sh` is for; the doctor is operational, not behavioral.
- **Cross-machine fleet view.** Each machine's doctor reports about itself. A "show me watcher status across all my Macs" view would build on `dotfiles secret push`-style multi-host SSH dispatch, out of scope here.
- **Linux.** Watcher is macOS-only per S-64; doctor follows the same constraint.
- **Inclusion in `dotfiles doctor`.** Tempting to fold this into the top-level health check, but `dotfiles doctor` today is "is your dotfiles installation sane" (managed file count, broken symlinks, etc.), not "are background subsystems healthy." Keep the audit pinned to the watcher's own namespace until there's a second background subsystem to consolidate with.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] `tests/dotfiles-watch.sh` passes 26/26 on Mac mini (17 prior + 9 new for S-66)
- [x] `/dotfiles-sync` skill section reviewed for visual layout fit (S-54): notify-only `[warn]/[err]` lines only, silent on health, slots between Secret cache and SA token rotation
- [x] Verified end-to-end on Mac mini 2026-05-13: clean state → six `[ok]` lines exit 0, `launchctl bootout` of fswatch agent → `[err] agent: com.truonghan.dotfiles-watcher-fswatch not loaded — Fix: dotfiles watch install` (exit 1), `launchctl bootstrap` re-mediation → silent again

## Implementation notes

- **Fingerprint storage**: chose the side-effect cache option (write `$HOME/.cache/dotfiles-watcher.managed.sha256` from the wiring script). Doctor diffs `chezmoi managed | sha256sum` against the cache. No plist surgery needed; the file is a one-line sha256 that's idempotently rewritten by the existing `run_onchange` flow.
- **Test helpers**: section 4 introduces `_make_fake_launchctl` (env-var driven, `FAKE_LC_WP` / `FAKE_LC_FS` control `running|loaded|missing`), `_make_fake_fswatch` (deleted by test 4.5 to simulate absence), `_seed_clean_fingerprint`, and `_run_doctor` (PATH shim + `DOTFILES_CHEZMOI` injection). The fake `chezmoi` shim from section 3 gains a `data` case that emits `{"headless": ${FAKE_HEADLESS:-false}}` for the headless-skip path.
- **Secret-guard interaction**: initial test draft used `deadbeef...` (64 hex chars) as a stale-fingerprint sentinel; secret-guard correctly flagged it as a possible private key / sha256. Replaced with `stale-fingerprint-non-hex-sentinel` (intentionally non-hex so it can never collide with a real sha256). Captures the discipline: even test fixtures that *look* secret-shaped trip the hook.
- **Why not fold into `dotfiles doctor`**: kept the audit pinned to the watcher's namespace. `dotfiles doctor` is "is your install sane"; this is "is a background subsystem healthy." Different concern. Revisit if a second always-on subsystem ever lands.
