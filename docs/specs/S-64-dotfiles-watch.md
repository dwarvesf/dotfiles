---
id: S-64
title: Continuous dotfiles watcher (live → repo working tree)
type: feature
status: proposed
date: 2026-05-12
extends: S-07, S-50
---

# S-64: Continuous dotfiles watcher

Extends [S-07](S-07-drift-detection.md) (one-shot drift detection / `dotfiles drift`) and [S-50](S-50-dotfiles-sync-skill-drift.md) (`/dotfiles-sync` skill catches new Claude skills) by closing the temporal gap: drift goes from "noticed when I run sync" to "absorbed as it happens." Working-tree only: `chezmoi re-add`, never `git commit`. Operator reviews via `git diff` and commits manually.

## Relationship to `/dotfiles-sync`

The watcher is **one slice** of what `/dotfiles-sync` does (the "absorb drifted files" slice), running automatically. `/dotfiles-sync` still owns everything the watcher deliberately punts on: new brew packages, new casks, new VS Code extensions, new fish functions, new SSH config fragments, new user-authored Claude skills, secrets cache state, SA-rotation prompts, classification decisions, commits, pushes.

Sequence in practice:

```
edit a managed file
      │
      ▼  (within ~3s)
watcher absorbs to working tree   ──►  source matches live, no commit
      │
      ▼  (when you have new stuff to track or want to commit)
/dotfiles-sync                    ──►  scans 10+ dimensions, classifies new
                                       things, commits, pushes
```

By the time you run `/dotfiles-sync`, the drift section of its report is empty (or close to it), so the report focuses on the decisions only a human can make (classify this brew core/local/skip, this skill belongs where, etc.) rather than on mechanical re-absorption.

## Problem

The existing drift paths (`dotfiles drift`, `/dotfiles-sync`) are operator-pull: drift accumulates silently between manual runs. Two patterns make this painful:

1. **In-place skill edits.** `~/.claude/skills/<name>/SKILL.md` gets edited multiple times per day during iteration. Each edit leaves drift that doesn't surface until the next `/dotfiles-sync`.
2. **Live IDE-config tweaks.** `~/.claude/settings.json`, `~/.config/zed/settings.json`, `~/.claude/keybindings.json`, `~/.claude/CLAUDE.md` get nudged constantly. Same accumulation problem.

Shape we want: edit a managed file → ~3s later the dotfile repo's working tree mirrors it. No commit. Operator decides when to commit.

The constraint on the trigger: launchd `WatchPaths` is **non-recursive on directories**. A watch on `~/.claude/skills` fires on *direct* child add/remove/rename but **not** on edits to `~/.claude/skills/<name>/SKILL.md`. Covers IDE-config tweaks (flat), misses the skill-edit case (the hot one). Pure `WatchPaths` therefore can't be the whole answer.

## Solution

Three components, all working-tree-only.

### 1. `dotfiles-watcher-tick` script

`home/dot_local/bin/executable_dotfiles-watcher-tick`. POSIX sh. One "tick" of the watcher; invoked by both LaunchAgents.

- **Lock**: `mkdir`-based atomic lock at `~/Library/Caches/dotfiles-watcher.lock`. macOS lacks `flock(1)` by default; `mkdir` is atomic on POSIX filesystems. Stale-lock forgiveness after 60s.
- **Debounce**: `sleep 2` before scanning for drift. Coalesces editor-save bursts (Zed writes `settings.json` 2-3 times in <100ms).
- **Drift loop**: up to `DRIFT_LOOP_MAX=3` passes of `chezmoi status | awk '/^ M /'` → `chezmoi re-add`. A file edited *during* a tick would otherwise be missed by a single-pass design.
- **Output**: appends to `~/Library/Logs/dotfiles-watcher.log` only when there is real drift to absorb (no noise on idle wakes). Per-pass `TICK start` / `TICK done (passes=N)` envelope.
- **Working-tree only**: never invokes `git add`, `git commit`, `git push`.

### 2. Two LaunchAgents, complementary coverage

| Agent | Trigger | Coverage |
|---|---|---|
| `com.truonghan.dotfiles-watcher.plist` | launchd `WatchPaths`, one leaf path per managed file (~117 entries). | Direct mtime change on any single managed file. Catches in-place skill edits because each `~/.claude/skills/<name>/SKILL.md` is its own leaf watch. |
| `com.truonghan.dotfiles-watcher-fswatch.plist` | `fswatch -r --latency 1` on `~/.claude`, `~/.config/zed`, `~/.config/fish`. KeepAlive=true. | Recursive coverage including subdirs created **after** the WatchPaths plist was last regenerated. Belt-and-suspenders for the watcher-staleness window. |

`WatchPaths` alone gives native, zero-process coverage for every currently-tracked file. fswatch alone would suffice for the file-events angle but needs a long-lived process and a brew dep (acceptable; ~5 MB RSS, ~200 KB binary). Running both is cheap (lock dedup) and the two cover each other's gaps.

### 3. Generated WatchPaths plist + `run_onchange` wiring

`home/.chezmoiscripts/run_onchange_after_dotfiles-watcher.sh.tmpl`. Re-fires whenever the `chezmoi managed` set changes (template embeds `{{ output "chezmoi" "managed" | sha256sum }}` so the source-hash flips with every adoption).

On run:

1. Walks `chezmoi managed`, filters to leaves that exist as files under `$HOME`.
2. Emits `~/Library/LaunchAgents/com.truonghan.dotfiles-watcher.plist` with one `<string>` per leaf in the `WatchPaths` array.
3. `plutil -lint` both plists.
4. `launchctl bootout gui/$UID/<label>` (tolerate non-zero — agent may not have been loaded) then `launchctl bootstrap gui/$UID <plist>` for each.

Skipped on `headless` (no IDE config to watch).

### 4. `dotfiles watch` subcommand

Operator surface on the existing `dotfiles` fish function:

| Verb | Behavior |
|---|---|
| `install` | Touch the wiring script (forces `run_onchange` re-fire) → `chezmoi apply`. |
| `uninstall` | `launchctl bootout` both agents. Plists stay on disk; re-install with `install`. |
| `status` | `launchctl print gui/$UID/<label>` for both agents, formatted compact. |
| `now` | Run `dotfiles-watcher-tick` once on demand (bypasses the watchers). |
| `tail` | `tail -F ~/Library/Logs/dotfiles-watcher.log`. |

## Test

Tests live in `tests/dotfiles-watch.sh`, self-contained bash, mirrors `tests/secret-guard.sh` style. No bats, no framework. Each block sets up an isolated `$HOME` under a mktemp dir and uses a fake `chezmoi` shim on the `DOTFILES_CHEZMOI` env override to simulate status/re-add output. Run from repo root: `bash tests/dotfiles-watch.sh`.

1. **shellcheck wrappers.** Both `home/dot_local/bin/executable_dotfiles-watcher-tick` and `executable_dotfiles-watcher-fswatch` pass `shellcheck -e SC2015` (project-wide `[ -f LIB ] && source LIB || die` idiom).
2. **Template renders.** `chezmoi execute-template` on the fswatch plist template and the `run_onchange` script template produce output that:
   - Fswatch plist: passes `plutil -lint`.
   - Wiring script: passes `bash -n`.
3. **No-op when clean.** Fake chezmoi returns empty `status`. Run a tick. Log file is empty (no `TICK start` line). Exit code 0.
4. **Single-pass absorb.** Fake chezmoi returns `' M .claude/settings.json'` on first `status`, empty on second. Run a tick. Log has exactly one `TICK start`, one `TICK done (passes=1)`, one `+ .claude/settings.json`.
5. **Drift loop terminates.** Fake chezmoi returns drift on passes 1 and 2, clean on pass 3. Log has `passes=2`. (Never hits the `DRIFT_LOOP_MAX=3` ceiling.)
6. **Lock coalesces.** Spawn two ticks in parallel (`&`). Wait. Log shows one `TICK start`, not two. The second instance's lock-acquisition fails and exits silently.
7. **Brewfile contains fswatch.** `grep -q '^brew "fswatch"' home/dot_Brewfile.tmpl`.

The fswatch-missing tests are deferred — they can't simulate "fswatch absent" on a machine where it's installed at `/opt/homebrew/bin/fswatch`. Pre-flight code paths are verified by shellcheck + visual review.

## Out of scope

- **Auto-commit / auto-push.** Explicit: the watcher never invokes git. Operator commits manually via `git status; git add; git commit` in the dotfiles repo. Rationale: silent commits to a public repo are a leak surface; review gate stays.
- **Auto-add of new files.** Watchers only fire on paths chezmoi already manages (since the WatchPaths plist is built from `chezmoi managed`, and fswatch events turn into no-ops if the path isn't managed — `chezmoi re-add` on an unmanaged path is a no-op error swallowed by the log). New files still go through `/dotfiles-sync` per S-50.
- **Linux.** `WatchPaths` and the deploy use macOS paths (`~/Library/LaunchAgents/`, `launchctl bootstrap`). Linux would need a systemd user-unit equivalent.
- **Per-second responsiveness.** 2s debounce + 1s fswatch latency = up to 3s end-to-end. Editor-save bursts under that window get coalesced into one tick; acceptable.
- **Conflict reconciliation.** If both source and dest changed independently (`MM` in `chezmoi status`), the watcher absorbs whichever side last fired the event. The `/dotfiles-sync` skill remains the operator path for surfacing `MM` and forcing a manual diff.
- **iOS / mobile.** SPEC-002 mobile pilot path runs over mosh into mac-mini-danang; this feature lives on the host you're physically editing on.

## Definition of done (per S-44)

- [ ] Spec frontmatter `status: done`
- [ ] Tick in `docs/tasks.md`
- [ ] Hostname-tagged entry in `docs/sync-log.md`
- [ ] `tests/dotfiles-watch.sh` passes on Hans-Air-M4
- [ ] User-facing section in `docs/guide.md` explaining install / status / tail
- [ ] One end-to-end demo on the user's machine: edit a managed file, observe log line, observe drift absorbed in dotfiles working tree
