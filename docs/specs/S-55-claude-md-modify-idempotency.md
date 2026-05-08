---
id: S-55
title: `modify_CLAUDE.md.tmpl` self-emits its idempotency marker
type: fix
status: done
date: 2026-05-08
---

# S-55: `modify_CLAUDE.md.tmpl` self-emits its idempotency marker

## Problem

`home/dot_claude/modify_CLAUDE.md.tmpl` is a chezmoi `modify_` script that
owns the canonical "Machines I work from / Tool selection / Tech stack
preferences / Security Rules / Self-verification rules" sections of
`~/.claude/CLAUDE.md`. It runs every `chezmoi apply` and is supposed to be
idempotent: strip everything below the `# --- END claude-context ---`
marker and re-append the canonical content.

The marker contract is broken. The script *consumes* the marker (uses it
to find the prefix boundary) but never *emits* it. The script's comment
header documents that an "upstream personal context generator" is supposed
to emit the marker as part of its prefix output. That generator either
doesn't exist, doesn't run on this machine, or has been silently regressed.

Result: the marker is never present in the live file. Each apply takes
the *whole* live file as PREFIX (the `else` branch), then appends the
canonical heredoc again. Every apply duplicates ~212 lines.

Snapshot 2026-05-08 @ Mac mini:

```
$ chezmoi apply ~/.claude/CLAUDE.md
$ wc -l ~/.claude/CLAUDE.md
1038
$ chezmoi apply ~/.claude/CLAUDE.md
$ wc -l ~/.claude/CLAUDE.md
1250  # +212, file grew with no source change
$ grep -c '^# Tech stack preferences$' ~/.claude/CLAUDE.md
6     # canonical content duplicated 4-6× depending on apply count
$ grep -c '^# --- END claude-context ---$' ~/.claude/CLAUDE.md
0     # marker never present
```

## Solution

Make the script self-emit the marker so it stops depending on a phantom
upstream generator. One-line change in the `else` branch:

```diff
 if printf '%s' "$INPUT" | grep -qxF "$MARKER"; then
     PREFIX="$(printf '%s' "$INPUT" | awk -v m="$MARKER" '{print} $0 == m {exit}')"
 else
-    PREFIX="$INPUT"
+    # First-run on this machine: marker absent. Append it to the prefix so
+    # subsequent applies find it and idempotency holds. (S-55)
+    PREFIX="$INPUT
+$MARKER"
 fi
```

Walkthrough:

- **First apply** (live file has no marker): PREFIX = INPUT + marker. Output = INPUT + marker + canonical.
- **Second apply** (live now has marker): PREFIX = INPUT-up-to-and-including-marker = same content as previous apply's PREFIX. Output identical. ✓ idempotent.

The script's comment header also gets a one-line update to drop the
"upstream generator" claim, since this script now owns the marker
unconditionally.

## Cleanup of bloated live files

Each affected machine has accumulated N copies of canonical content. The
fix alone won't shrink existing files; users need a one-time cleanup. The
cleanup is mechanical:

```bash
# 1. Find first canonical landmark (first occurrence of the heredoc start)
LINE=$(grep -n '^# Machines I work from$' ~/.claude/CLAUDE.md | head -1 | cut -d: -f1)
# 2. Truncate to upstream-prefix only (everything before that line)
head -n $((LINE - 1)) ~/.claude/CLAUDE.md > ~/.claude/CLAUDE.md.upstream-only
# 3. Move into place
mv ~/.claude/CLAUDE.md.upstream-only ~/.claude/CLAUDE.md
# 4. chezmoi apply now adds marker + 1 clean canonical block
chezmoi apply ~/.claude/CLAUDE.md
# 5. Verify idempotency
BEFORE=$(wc -l < ~/.claude/CLAUDE.md); chezmoi apply ~/.claude/CLAUDE.md
AFTER=$(wc -l < ~/.claude/CLAUDE.md)
[ "$BEFORE" = "$AFTER" ] && echo "idempotent ✓" || echo "still growing ✗"
```

Mac mini today: live had 4 cycles of canonical content (1038 lines, +848
above the ~190-line upstream prefix). After cleanup + fixed apply, the
file should land at ~190 + 1 marker line + 212 canonical = ~403 lines,
and stay there across repeated applies.

## Test

1. **Unit: marker self-emit on first run.** Pipe a marker-less buffer through
   the rendered modify script:

   ```bash
   echo "# upstream content
   line two" | bash <(chezmoi cat-config ... modify_CLAUDE.md.tmpl)
   ```
   Expected: output ends with `# --- END claude-context ---` BEFORE the
   canonical heredoc. (Adjust invocation to match how chezmoi materializes
   the script; the practical test is step 2.)
2. **Integration: idempotency.** On a machine with the bug, run the cleanup
   recipe above. Apply once. Capture line count A. Apply again. Capture
   line count B. Assert `A == B`.
3. **Cross-machine.** After Mac mini cleanup, pull on Mac Air M4 next time
   it syncs. The Air's CLAUDE.md should also get cleaned up by the same
   recipe (the Air has its own bloat from the same bug).
4. **Spec discipline (S-44).** This spec ships with `status: done` only
   after: (1) the fix lands in `modify_CLAUDE.md.tmpl`, (2) Mac mini's
   live file is cleaned up, (3) idempotency is empirically verified by
   double-apply, (4) tasks.md ticks S-55, (5) hostname-tagged sync-log
   entry on the cleanup machine.

## Out of scope

- **Upstream "personal context generator"** — not investigating where it
  was supposed to come from or why it's missing. The script is now
  self-sufficient; the upstream is no longer load-bearing.
- **De-duplicating the upstream prefix.** Mac mini's upstream prefix
  itself has `# Tech stack preferences` and `# Security Rules` repeated
  twice (lines 34 + 113). Those are user-personal content (`~/.claude/
  CLAUDE.md` is the user's global Claude Code config) and not this
  script's responsibility to fix. User can de-dupe manually if desired.
- **Rolling back canonical content changes** to past dates. The canonical
  heredoc contents are part of the file; future revisions track via
  normal git history.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] Mac mini live file cleaned up; idempotency double-apply verified
