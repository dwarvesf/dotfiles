---
id: S-56
title: Personal preferences move into the dotfiles modify-script (above-marker → canonical)
type: refactor
status: done
date: 2026-05-08
---

# S-56: Personal preferences move into the dotfiles modify-script

## Problem

The user's `# Personal preferences` block (tone-and-feedback, formatting,
visuals, visual theme defaults) lives in `~/.claude/CLAUDE.md` lines 1-32
on every machine. That content is **manually written**, not under version
control, and doesn't survive a fresh-machine bootstrap. A new Mac Mini /
Air / VM has zero personal preferences until the user copy-pastes them
back in.

S-55 documented the design as "above-marker = upstream personal context
generator, below-marker = canonical heredoc," but the upstream generator
is a phantom. The user has been manually maintaining the above-marker
region. That works on the daily driver but is fragile across machines
and degrades silently.

Symptom on Mac mini today (post-S-55 cleanup, 403 lines):

```
$ head -3 ~/.claude/CLAUDE.md
# Personal preferences

Applied to every project. ...

$ git ls-files home/dot_claude/ | xargs grep -l 'Personal preferences'
(empty)   # not in dotfiles anywhere
```

The user's mental model expects this content to "just be there" on every
machine. It isn't.

## Solution

Move the canonical `# Personal preferences` content into
`home/dot_claude/modify_CLAUDE.md.tmpl`, prepended to the existing heredoc
above `# Machines I work from`. Same modify script that already manages
the canonical region (post-S-55) now manages personal preferences too.

Above-marker becomes effectively empty on a fresh machine — the modify
script is the single source of truth for the entire post-marker file
content.

### Diff outline

```diff
 cat <<'MARKDOWN'

+# Personal preferences
+
+Applied to every project. Project-level `CLAUDE.md` files may add on
+top of these but should not contradict without good reason.
+
+## Tone and feedback
+
+- Be brutally honest. Do not be a yes-man.
+- If I am wrong, point it out bluntly.
+- I need honest feedback on my code, not reassurance.
+- Challenge my reasoning when you see a flaw, even if I seem committed
+  to a direction.
+- Disagreement is useful. Agreement for its own sake is not.
+
+## Formatting
+
+- Do NOT use em dashes in responses. Use commas, colons, parentheses,
+  or separate sentences instead.
+- Prefer short direct sentences over long ones with multiple clauses.
+- No filler, no preamble, no recap of what I just asked.
+
+## Visuals
+
+- I am a visual learner. Lead with a diagram or table before prose
+  when explaining architectures, flows, or comparisons.
+- In terminal output use ASCII / box-drawing diagrams, markdown tables,
+  or tree structures.
+- When generating image, SVG, or PNG artifacts (canvas-design,
+  diagrams, charts), use a **light theme**: light background, dark
+  text and lines.
+- If a concept has no good visual, skip forcing one. Do not invent
+  meaningless diagrams.
+
+## Visual theme defaults (for generated artifacts)
+
+- Background: white (`#ffffff`) or very light gray (`#fafafa`)
+- Primary text: near-black (`#111827`)
+- Lines / borders: dark gray (`#374151`)
+- Accent: a single muted color, not neon
+- Fonts: system sans for UI diagrams, mono for code-adjacent visuals
+
 # Machines I work from

 The SessionStart hook prints `Machine: ...
```

### Cleanup recipe (per machine)

The above-marker region currently contains these manual sections:

```
# Personal preferences        ← keep, but move source to dotfiles
# Tech stack preferences       ← ALREADY in canonical heredoc; remove from upstream
# Security Rules               ← ALREADY in canonical heredoc; remove from upstream
# Self-verification rules     ← ALREADY in canonical heredoc; remove from upstream
```

So the above-marker region collapses to **empty** after this spec. Live
file becomes essentially `marker + canonical` (where canonical now
includes Personal preferences).

```bash
# 1. Truncate above-marker to nothing (only safe AFTER S-56 fix is in source)
LINE=$(grep -n '^# --- END claude-context ---$' ~/.claude/CLAUDE.md | cut -d: -f1)
tail -n +"$LINE" ~/.claude/CLAUDE.md > /tmp/claude-md-from-marker.txt
cp /tmp/claude-md-from-marker.txt ~/.claude/CLAUDE.md

# 2. Apply: regenerates everything below marker
chezmoi apply ~/.claude/CLAUDE.md

# 3. Verify
A=$(wc -l < ~/.claude/CLAUDE.md); chezmoi apply ~/.claude/CLAUDE.md
B=$(wc -l < ~/.claude/CLAUDE.md)
[ "$A" = "$B" ] && echo "✓ idempotent post-S-56"
grep -c '^# Personal preferences$' ~/.claude/CLAUDE.md   # should be 1
grep -c '^# Tech stack preferences$' ~/.claude/CLAUDE.md # should be 1 (down from 3 pre-S-56)
```

## Test

1. **Source has Personal preferences.** `grep '# Personal preferences'
   home/dot_claude/modify_CLAUDE.md.tmpl` returns the section content.
2. **Single canonical copy on apply.** After cleanup recipe + apply,
   `grep -c '^# Personal preferences$' ~/.claude/CLAUDE.md` is exactly
   `1`. Same for `# Tech stack preferences`, `# Security Rules`,
   `# Self-verification rules` (currently 3 each on Mac mini due to
   the upstream-duplication leftover from before S-55).
3. **Idempotency preserved.** Double-apply produces identical line count.
4. **Fresh-machine simulation.** With `~/.claude/CLAUDE.md` deleted (or
   minimal `# placeholder` content), `chezmoi apply ~/.claude/CLAUDE.md`
   produces a file that contains all five sections (Personal, Machines,
   Tool selection, Tech stack, Security, Self-verification). User-snippet
   keywords ("brutally honest", "em dashes", "visual learner",
   "light theme") all appear.
5. **Cross-machine.** Mac Air M4 will hit the same cleanup recipe next
   time it syncs; should land at the same line count + section list as
   Mac mini.

## Out of scope

- **Choosing different content** for personal preferences. This spec
  preserves the user's existing wording verbatim (the live Mac mini
  copy at `~/.claude/CLAUDE.md` lines 1-32 as of 2026-05-08 21:30).
  Future revisions go through normal git history.
- **Splitting personal preferences into a separate file.** Keeping it
  in the modify-script heredoc is simpler than introducing a second
  managed file just for this.
- **Restoring the phantom upstream generator.** S-55 already declared
  it not load-bearing. S-56 confirms by removing the only above-marker
  content (Personal preferences was the last reason for non-empty
  prefix).

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] Mac mini live file cleaned + idempotency double-apply verified
