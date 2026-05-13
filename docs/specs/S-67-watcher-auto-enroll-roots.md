---
id: S-67
title: Watcher auto-enrolls new files under designated roots
type: feature
status: done
date: 2026-05-13
extends: S-64, S-65, S-66
---

# S-67: Watcher auto-enrolls new files under designated roots

Extends [S-64](S-64-dotfiles-watch.md) by closing the new-file gap. Today the watcher absorbs edits to **already-managed** files but silently ignores brand-new files inside its watched roots. The hot case is `~/.claude/skills/<name>/SKILL.md`: a freshly created skill is invisible to the watcher until the operator manually `chezmoi add`s it. Found 2026-05-13 after two new skills shipped (`ops-tool-shape`, `ops-tool-docs`) and the watcher's drift loop never picked them up.

## Problem

S-64's tick filters `chezmoi status` to `^.M ` rows only. The current tick script (`home/dot_local/bin/executable_dotfiles-watcher-tick` line ~79) is explicit about this:

```sh
# ` A ` (new file untracked-by-chezmoi) is intentionally skipped
# per S-64 § Out of scope.
DRIFT=$("$CHEZMOI" status 2>/dev/null | awk '/^.M / {print substr($0,4)}')
```

New files don't appear in that filter, and `chezmoi status` doesn't list paths chezmoi has never seen at all. Result: the fswatch sibling correctly fires when a new file is created under `~/.claude/skills/`, but the tick's drift loop finds nothing to absorb.

This is the right default for files like `~/.config/fish/fish_history` (transient, never want to track) but the wrong default for SKILL.md files (always want to track, no exception). The cost of the manual step is real:

1. **Discovery is delayed.** The operator only notices when `/dotfiles-sync` runs and surfaces "new skill" in the classification list. Hours to days after creation.
2. **The skill iteration loop breaks.** Edit the SKILL.md during authoring, save, no absorb (because the file isn't managed). Realize, `chezmoi add`, edit again, now it absorbs. Annoying.
3. **S-64's design promise is "edit, ~3s, mirrored in repo working tree"** for managed files. A new file silently violates that promise for an unbounded window.

Concrete reproduction: today `~/.claude/skills/ops-tool-shape/SKILL.md` and `~/.claude/skills/ops-tool-docs/SKILL.md` exist on the Mac mini (created 2026-05-13). `chezmoi managed | grep ops-tool` returns empty. The dotfiles repo working tree is clean. No entry in the watcher log mentions either file.

## Solution

Add an **auto-enroll** pass to the tick, gated by a hard-coded glob list. Files matching an auto-enroll glob get `chezmoi add`-ed if they are not yet managed. After enrollment they participate in the normal drift loop on subsequent ticks.

### 1. Auto-enroll globs

Constant near the top of `home/dot_local/bin/executable_dotfiles-watcher-tick`:

```sh
# Files matching any of these globs get auto-enrolled (chezmoi add) on tick
# if they exist but are not yet managed. New entries here are the only way
# to add new auto-enroll behavior; the watcher does NOT scan arbitrary
# unmanaged files.
AUTO_ENROLL_GLOBS='
${HOME}/.claude/skills/*/SKILL.md
'
```

Start with **one entry**: skill files. Resist generalizing until the second auto-enroll case shows up. The list is intentionally narrow (`*/SKILL.md`, not whole subtrees) to avoid catastrophes like `chezmoi add`-ing a 10 MB log file someone dropped in.

### 2. Tick scan

In the drift loop, **before** the existing `chezmoi status` pass, add an enrollment pass:

```sh
# Enroll matching unmanaged files. Idempotent: gate on managed-set membership
# so we don't spend a chezmoi-add invocation per tick on every glob match.
managed_set=$("$CHEZMOI" managed 2>/dev/null)
echo "$AUTO_ENROLL_GLOBS" | while IFS= read -r glob; do
    [ -z "$glob" ] && continue
    eval "for f in $glob; do
        [ -f \"\$f\" ] || continue
        rel=\"\${f#\$HOME/}\"
        if ! printf '%s\n' \"\$managed_set\" | grep -Fxq \"\$rel\"; then
            if \"\$CHEZMOI\" add \"\$f\" >>\"\$LOG\" 2>&1; then
                printf '  + enrolled %s\n' \"\$rel\" >> \"\$LOG\"
            fi
        fi
    done"
done
```

If enrollment happens, the chezmoi managed-set hash flips. The existing `run_onchange_after_dotfiles-watcher.sh.tmpl` re-fires on the next `chezmoi apply`, regenerating the WatchPaths plist with the new leaf. Until that next apply, the fswatch sibling covers the new file (it lives under a recursive watched root). No race window where the file is unwatched.

### 3. Log format

Distinguish enroll from absorb:

```
2026-05-13T15:04:01Z TICK start
  + enrolled .claude/skills/ops-tool-docs/SKILL.md
  + enrolled .claude/skills/ops-tool-shape/SKILL.md
2026-05-13T15:04:03Z TICK done (passes=1)
```

Existing `+ <path>` lines stay as-is for the re-add case. `+ enrolled <path>` is the only new format.

### 4. No plist generator change

`home/.chezmoiscripts/run_onchange_after_dotfiles-watcher.sh.tmpl` does not need to change. Its `managed-set fingerprint` line already re-fires whenever chezmoi adds a new file, so the next `chezmoi apply` after an enrollment will regenerate WatchPaths with the new leaf. No new WatchPath needed at the launchd layer because fswatch already recursively covers `~/.claude/`, `~/.config/zed`, and `~/.config/fish`.

## Test

New cases in `tests/dotfiles-watch.sh` (existing suite is 26 after S-66; this adds 4 more):

1. **Auto-enroll: new SKILL.md, not yet managed.** Fake `chezmoi managed` returns set without the path. Create `$HOME/.claude/skills/foo/SKILL.md`. Run tick. Log contains `+ enrolled .claude/skills/foo/SKILL.md` exactly once. Fake `chezmoi add` was called with the absolute path.
2. **Idempotent: already-managed SKILL.md.** Fake `chezmoi managed` returns set including the path. Run tick. Log contains zero `+ enrolled` lines. `chezmoi add` was not called.
3. **Glob discipline: non-SKILL files inside a skill dir are not enrolled.** Create `$HOME/.claude/skills/foo/README.md` (no SKILL.md). Run tick. Log empty for enroll. `chezmoi add` not called.
4. **Mixed pass: enroll + absorb in one tick.** Fake status reports `.M .claude/settings.json` AND an unmanaged `$HOME/.claude/skills/new/SKILL.md` exists. Run tick. Log has both `+ enrolled .claude/skills/new/SKILL.md` and `+ .claude/settings.json`. Exit 0. `passes=1` line printed.

End-to-end on the Mac mini after install:

```sh
chezmoi forget ~/.claude/skills/ops-tool-shape/SKILL.md   # de-manage
touch ~/.claude/settings.json                              # poke a watched file
sleep 5
tail -20 ~/Library/Logs/dotfiles-watcher.log
# expect: `+ enrolled .claude/skills/ops-tool-shape/SKILL.md`
chezmoi managed | grep ops-tool-shape                      # back in the set
```

## Out of scope

- **Auto-commit.** S-64's working-tree-only invariant stands. Enrollment writes to the chezmoi source state but does not `git add` / `git commit`. Operator reviews via `git status` in the dotfiles repo and commits manually, same as today.
- **Generalized "watch directory X" config.** No `~/.config/dotfiles-watch-roots` file, no chezmoi-data merge, no per-machine override. One hard-coded glob list in the tick script; extension means editing the script and shipping it. Resist the configurability tax until the second use case lands.
- **Auto-enrollment of broader skill subtree.** Only `SKILL.md` is enrolled, not the skill's `references/`, `templates/`, or `WORKFLOW.md` files. Once SKILL.md is managed and edited, the operator commits and decides what other paths belong; `/dotfiles-sync`'s skill-classification still surfaces the rest.
- **Linux.** S-64 was macOS-only; S-67 inherits.
- **Surface in `dotfiles watch doctor`.** The doctor's existing checks cover agent health, not policy. "Auto-enrolled N files in the last 7 days" would be a useful counter but adds a state file (auto-enroll history) and is not load-bearing for the watcher's correctness.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] `tests/dotfiles-watch.sh` passes 30/30 (26 prior + 4 new for S-67)
- [x] Verified end-to-end on Mac mini 2026-05-13: post-merge `dotfiles watch install` + `dotfiles watch now` enrolled 8 unmanaged skills in one pass (ops-tool-shape, ops-tool-docs, agency-lead-radar, image-spec, peon-ping-{config,log,toggle,use}). Log shows `+ enrolled` line per skill, `TICK done (passes=0)` confirms the pure-enroll case. `chezmoi managed | grep ops-tool` returns both rows. First-tick batch revealed the gap was wider than the 2 known cases.
- [x] `/dotfiles-sync` skill text not updated: the drift section already accepts `+ <path>` lines, so `+ enrolled <path>` is a strict superset of the format. No surprise in the rendered Drift section.

## Implementation notes

- **Glob expansion**: the `eval` is intentional, to expand `*` in `${HOME}/.claude/skills/*/SKILL.md`. `find` would also work but adds a fork per glob and a regex argument; the eval form keeps the tick fast and POSIX. The eval input is the hard-coded `AUTO_ENROLL_GLOBS` constant, never user input.
- **Throughput**: typical enroll case is 0 or 1 files per tick. The `grep -Fxq` short-circuit ensures we don't pay the chezmoi-add cost on every tick once a file is enrolled. Worst case (first run after many new skills): one chezmoi-add per skill, ~50-100ms each, well within the tick's existing 2s debounce window.
- **Failure handling**: if `chezmoi add` fails (permission, disk full, etc.), the log line `+ enrolled ...` is NOT printed (the if-success guard skips it). The error goes to the same log via `>>"$LOG" 2>&1`. Tick continues to the next file and to the existing drift pass. No tick-abort on enroll failure.
- **Why not extend `chezmoi status` parsing instead**: chezmoi status does not emit a row for unmanaged files, even with include-all flags. The format is "things chezmoi knows about." Auto-enroll has to be a separate scan; folding it into the status parse would require upstream chezmoi changes.
- **Why not move enrollment to `/dotfiles-sync`**: the whole point of S-64 was to shorten the absorb loop from "minutes-to-hours" to "~3s." Punting enrollment to `/dotfiles-sync` re-introduces the gap for the specific files (new skills) where the iteration loop hurts most.
