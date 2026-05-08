---
id: S-54
title: `/dotfiles-sync` report uses a delta-inspired, scannable diff layout
type: feature
status: done
date: 2026-05-08
---

# S-54: `/dotfiles-sync` report uses a delta-inspired, scannable diff layout

## Problem

`/dotfiles-sync` produces a per-machine snapshot that classifies drift across
many surfaces (chezmoi config, Brewfile, casks, VS Code extensions, fish
functions, SSH fragments, Claude skills, secrets cache, guardrails pin). Pre-
S-54, that snapshot was rendered as a flat sequence of bulleted sections with
counts and names. The output was *correct* but visually undifferentiated —
every section read the same; sync direction (apply vs re-add vs reconcile)
required reading the heading text; conflicts didn't visually outweigh
informational notices; long lists wrapped unpredictably; and the user spent
scan-budget that should have gone to decisions.

The user explicitly asked for the report to feel like git-`delta`'s diff
viewer — colored row markers, clear hunk separators, dense but breathable.
After several iterations on color, layout, separator glyphs, tag placement,
and decoration density, a settled design emerged. This spec captures it so
future edits to the prompt don't re-litigate choices that are already
load-bearing.

## Solution

The `/dotfiles-sync` Step 3 report uses a single fenced code block per run,
with `─── emoji Title ───` dividers between sections, an emoji-coded marker
column on each row, and explicit decoration in the bottom-half informational
sections. Five design pillars:

### Pillar 1 — Single fenced block, text dividers

The diff body is **one** ` ```text ... ``` ` block. Section breaks use
`─── <emoji> <Title> — <subcommand-or-context> ───` lines *inside* the block,
not markdown `###` headings. Markdown headings adjacent to fenced blocks
introduce an unavoidable blank line in Claude Code's renderer — verified
visually in 2026-05-08 iterations. Inline dividers eliminate the gap.

A blank line precedes every divider except the first, giving sections
breathing room. Zero blank line *after* the divider; the first row sits
flush below it.

### Pillar 2 — Emoji palette (organic + alert metaphors)

The marker palette intentionally avoids the round colored circles
(🟢🟡🔴🟠🟣⚪) — they read as generic indicators, not semantic signals.
Settled palette:

| Marker | Emoji | Meaning | Mood |
|---|---|---|---|
| `+` | 🌿 | added | growth |
| `-` | 🔻 | removed / superseded | down-shift |
| `~` | 🌀 | modified / drift | motion |
| `‼` | ⚠️ | conflict | attention |
| `·` | ⚪ | notify-only | quiet |
| (bucket) | 👾 | classify (core/local/skip) | unknown |
| (stale) | 🔸 | pseudo-stale | soft warning |

Status icons (Notify-only section):

| Icon | Meaning |
|---|---|
| 🍃 | check passed |
| ⚠️ | non-blocking warning |
| ❌ | failure / urgent |

ASCII glyphs (`+ - ~ ‼ ·`) sit alongside the emoji on each row so the
structure survives copy-paste into a terminal that strips emoji.

### Pillar 3 — Strict row format with inline tags

```
<emoji> <ascii-marker> <padded-path>  <description> [tag]
```

- Path padded to longest in section, capped at 46 chars; longer paths front-truncate with `…`.
- Two-space gap between path and description (no `⇒` glyph — wastes a column).
- Description ≤ 40 chars to prevent wrap; longer content summarized as `+N items (a, b, …)`.
- `[tag]` inline at end, single-space gap. Tag right-alignment was tried and
  rejected — the long pad-stretches read as visual noise. Inline is denser.
- `→` reserved for value transitions inside descriptions
  (`python 3.12.10 → 3.12.13`); never overload the row marker glyph.

### Pillar 4 — Section ordering and divider colors

| Section | Divider | Direction |
|---|---|---|
| Pending apply (repo → machine) | 🌿 | `chezmoi apply` |
| Drift to absorb (machine → repo) | 🌀 | `chezmoi re-add` |
| Conflict (both sides) | ⚠️ | manual reconcile |
| Untracked installs | 👾 | classify |
| Stale Brewfile entries | 🔸 | cleanup |
| Already local | ⚪ | informational |
| Notify-only | ⚪ | informational |
| Recommended order | ✨ (markdown heading, outside the block) | action plan |

Empty section → omit the divider entirely; no placeholders.

### Pillar 5 — Bottom-half decoration

Informational sections (Untracked / Stale / Already local / Notify-only) read
as a flat wall of text without explicit decoration. Each gets a distinct
visual treatment:

- **Untracked installs.** Bucket pill (🔻 superseded / 👾 classify / 👾 casks)
  followed by indented `•` bullet groups, items broken into 1-2 visual rows
  per bucket. No 11-name single line.
- **Stale Brewfile entries.** Boxed count `[N phantom]` after the path,
  description and entry list on a continuation line, indented under the path.
- **Already local.** Every row gets a `⚪▮` pill prefix matching diff-row
  cadence. Sub-buckets use `▸ kind (count): …`. Missing files use `✗` marker.
- **Notify-only.** Every row leads with a status icon (🍃 / ⚠️ / ❌) so the
  reader can answer "should I look?" before parsing text. Multi-line follow-
  ups indent under their parent row.

## Header block

The report opens with a 2-line summary inside its own fenced block:

```
sync <ts>  @ <hostname>  rev <sha>  <wide|narrow>
🌿 N pending  ·  🌀 N drift  ·  ⚠️ N conflict  ·  👾 N+M untracked  ·  ⚪ N/M ssh-key
```

Zero counts are omitted from the second line so it collapses gracefully when
little has changed.

## Responsive layout

Width detection cascade:

```bash
COLS=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
```

A balance check guards the two-column layout: `RATIO = max(L,R)/min(L,R)`.
Two-column only earns its keep when `COLS >= 140` *and* `RATIO < 4` *and*
both sides have ≥3 rows. Otherwise single-column. The 19/2 case from the
2026-05-08 iteration (RATIO 9.5) made the empty right column read as wasted
space; the rule prevents recurrence.

`tput cols` returns 80 inside Claude Code's Bash sandbox (non-TTY) even on a
wide UI window — the spec's bash cascade falls back to single-column there,
which is always safe. The user can override per-run by saying "wide" /
"narrow."

## Hard rules

- **No markdown tables.** Claude Code's renderer draws cell borders on every
  row; the heavy grid destroys the dense delta look. Use fenced code blocks
  with manual alignment.
- **Tag vocabulary.** `[new] [mod] [del] [conflict] [stale] [pseudo-stale]
  [superseded] [private] [clean] [local]`. Lowercase, bracketed, inline.
- **Description ≤ 40 chars.** Longer content gets summarized.
- **Collapse ≥5 identical descriptions** into one summary row + bullet list
  (e.g. "10 skills from PR #76" + 10 names).
- **One blank line before each divider, zero after.**
- **Recommended order section is markdown** (outside the fenced block) — it's
  an action plan, not a diff.

## Test

1. **Visual sanity (manual).** Trigger `/dotfiles-sync` on a machine with at
   least one item in each direction (Pending apply, Drift, Conflict). Verify:
   - Single fenced code block contains all sections.
   - `─── 🌿 Pending apply — chezmoi apply ───` divider above its rows.
   - Blank line precedes every divider except the first.
   - Each row leads with `<emoji> <ascii>` (e.g. `🌿 +`, `🌀 ~`, `⚠️ ‼`).
   - Tags inline at end, no trailing pad-stretch.
   - Status icons (🍃 / ⚠️) lead every Notify-only row.
2. **Empty section omission.** On a clean sync (zero drift), only the header
   block + Notify-only section render. No empty `─── ... ───` dividers.
3. **Description truncation.** Edit `~/.Brewfile` to add 5+ entries beyond
   the source. Sync should render `🌀 ~ ~/.Brewfile  +5 brews (a, b, …) [mod]`,
   not the full list. Full list belongs in the commit message at apply time.
4. **Balance check.** Synthesize a 19/2 split (many pending, few drift).
   Layout must drop to single-column even on a 200-col terminal.
5. **Prompt source vs deployed parity.** `diff .claude/commands/dotfiles-sync.md
   home/dot_claude/commands/dotfiles-sync.md` returns exit 0 after `chezmoi
   apply`.
6. **No markdown tables in report.** `grep -E '^\|.*\|' <(invoke /dotfiles-sync)`
   returns no matches inside the diff body. (Tables are still permitted in
   the *prompt's instructional content*, just not in the rendered report.)

## Out of scope

- **ANSI escape colors.** Stripped by markdown code-fence renderer; only
  emoji survive. Real row-background highlighting (delta's killer feature) is
  not achievable here. Colored squares were tried and rejected as a
  substitute (user preferred organic emoji).
- **Two-column layout for narrow runs.** Documented in 3e of the prompt but
  rarely engaged in practice — the balance check + non-TTY width detection
  drop most runs to single-column.
- **Internationalization.** The prompt assumes English copy; tag vocabulary
  is fixed.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
