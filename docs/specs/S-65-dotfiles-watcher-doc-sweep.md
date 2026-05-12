---
id: S-65
title: Post-ship doc sweep for the S-64 watcher
type: docs
status: done
date: 2026-05-12
extends: S-64
---

# S-65: Post-ship doc sweep for the S-64 watcher

[S-64](S-64-dotfiles-watch.md) shipped the background watcher (`dotfiles watch` / `dotfiles-watcher-tick` / two LaunchAgents). The feature merged via dwarvesf/dotfiles#98 and the deploy-time regex fix via #99. **The surrounding onboarding + skill docs were written before S-64 and now contain stale or actively misleading claims.** This spec captures the doc sweep so the post-state is locked in by tests.

## Problem

A repo audit on 2026-05-12 (broad scope) found one actively-wrong claim and four "now-incomplete" surfaces:

| File | Status | Detail |
|---|---|---|
| `docs/llm-dotfiles.md` line 276 | 🔴 actively wrong | Literal: *"No daemon, no watcher. You trigger the sync when you want it."* Was true pre-S-64. False now. |
| `README.md` pitch + cheat sheet | 🟡 incomplete | Frames `/dotfiles-sync` as the only maintenance path. Cheat sheet ("Catch up after drift → /dotfiles-sync") doesn't mention the watcher. |
| `install.sh` | 🟡 incomplete | Bootstrap ends without telling new operators about the optional watcher. |
| `home/dot_claude/commands/dotfiles-sync.md` (the `/dotfiles-sync` skill) | 🟡 incomplete | Step 2 "Scan for drift" presents itself as the only drift path. Empty drift list will become common with the watcher running, and the skill should set that expectation explicitly. |
| `docs/decisions/006-auto-commit-workflow.md` | 🟡 worth a clarification | Decision: *"commit-on-change is the default for all dotfile editing workflows."* The watcher deliberately does NOT auto-commit. Strict reading of the ADR would conflict with the watcher's design. |

Without this sweep, a new operator (or a future Claude session) reading the docs cold would be confused about whether the watcher exists, when to use it vs `/dotfiles-sync`, and why the watcher breaks the commit-on-change ADR rule.

## Solution

Five targeted edits. No new code paths, no behavior changes — purely doc.

### 1. Fix the actively-wrong `docs/llm-dotfiles.md`

Replace the "No daemon, no watcher" passage with a section explaining the watcher's role and how it complements the Claude-driven `/dotfiles-sync` workflow. Frame the relationship: watcher = always-on, mechanical, one slice (drift absorb); `/dotfiles-sync` = on-demand, judgment-laden, broad (new files, classification, commits, pushes).

### 2. README.md updates

- Pitch line (L11 region): one sentence acknowledging the watcher closes the temporal gap.
- Cheat sheet (L103 area): new row for `dotfiles watch install` / drift-absorbed-as-you-save.
- Two-layer model section (L54): namedrop S-64 as the always-on counterpart so the reader knows it exists when they're reading about chezmoi's source/target model.

### 3. install.sh next-steps hint

At end of successful bootstrap, append a single line pointing to `dotfiles watch install` as an opt-in next step. **Do not auto-install the watcher** — that's a separate behavior decision out of scope here.

### 4. `/dotfiles-sync` skill Step 2 note

Add a short paragraph at the top of Step 2 "Scan for drift" explaining that on machines where `dotfiles watch` is running, the Drift section of the report will usually be empty. Empty is **not** a signal that something is broken — it's the expected steady state.

### 5. ADR-006 watcher-exception paragraph

Append a paragraph to the Decision section (or as an addendum at the bottom) clarifying that S-64 is a deliberate, explicit exception to the commit-on-change rule. Watcher absorbs drift to the working tree only; the operator commits after `git diff` review. Rationale: no human authored the absorption, so the commit gate is the only review surface left.

## Test

Tests live in `tests/dotfiles-watch.sh` (extended from S-64), as a new section "6. Docs cross-references." Self-contained grep checks; no framework. Each case is a function returning 0/1 against the post-state of the touched files. Run from repo root.

1. **No stale "no daemon" phrase.** `grep -F "No daemon, no watcher" docs/llm-dotfiles.md` returns nothing.
2. **`docs/llm-dotfiles.md` mentions the watcher.** `grep -F "dotfiles watch" docs/llm-dotfiles.md` returns at least one hit; same for `S-64`.
3. **README cheat sheet has a watcher row.** `grep -F "dotfiles watch" README.md` returns at least one hit.
4. **README two-layer model section names S-64.** `grep -F "S-64" README.md` returns at least one hit (cross-reference).
5. **`install.sh` mentions the watcher as a next step.** `grep -F "dotfiles watch" install.sh` returns at least one hit.
6. **`/dotfiles-sync` skill acknowledges the watcher in Step 2.** `grep -F "dotfiles watch" home/dot_claude/commands/dotfiles-sync.md` returns at least one hit.
7. **ADR-006 has the watcher exception.** `grep -E "S-64|watcher.*exception|exception.*watcher" docs/decisions/006-auto-commit-workflow.md` returns at least one hit.

## Out of scope

- **Auto-installing the watcher in `install.sh`.** Behavior change. Separate decision, separate spec. v1 is opt-in via `dotfiles watch install`.
- **Recreating `.claude/commands/dotfiles-sync.md` mirror** (per [S-50](S-50-dotfiles-sync-skill-drift.md) — the byte-identical project copy). The mirror is currently absent from the repo. Either it was never created or got removed; outside this sweep.
- **Updating SVG diagrams** under `docs/dotfiles_*.svg`. Several reference the sync flow; redrawing them is a separate doc task and probably not load-bearing.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md` (Mac mini)
- [x] `tests/dotfiles-watch.sh` passes including the new section 6 (17/17 on Mac mini, up from 10/10)
- [x] All five files updated and grep tests pass
