---
name: md-preview
description: Use when Han asks to render or preview a markdown file in the browser, especially math-heavy documents with `$...$` or `$$...$$` LaTeX. Trigger phrases include "render this markdown", "preview Day-NN-explained", "open X.md in browser", "show me X as HTML", "render the explained doc", "/md-preview", or any time Han points at a `.md` file and wants to view it with KaTeX-rendered math. Wraps the `md-preview` CLI at `~/workspace/tieubao/ops-toolkit/tools/md-preview/` (which itself wraps `pandoc --katex`). NOT for plain `.md` reading (open the file directly). NOT for generating new markdown content. NOT for non-markdown formats.
---

# /md-preview

Render a markdown file (with KaTeX-rendered LaTeX math) to a self-contained HTML file via the `md-preview` CLI, then surface the `file://` URL to Han so he can click it open in his browser.

Built because Zed's markdown preview does not render LaTeX as of May 2026, and any math-heavy file in `learning/<topic>/courses/*/Day-NN-explained.md` is unreadable in Zed without this workaround.

## When to use

- Han says "preview this markdown", "render X.md", "open X.md in browser", "show me as HTML".
- Han pastes a `.md` path and asks how to view it.
- Han asks "where's the rendered version of Day-NN-explained?"
- Han invokes `/md-preview <path>` explicitly.
- A learning-day-process or similar workflow just produced a math-heavy `.md` and Han needs to look at the result.

## When NOT to use

- Han wants to *read* plain prose markdown (no math, no tables) → just open the file in Zed directly.
- Han wants to *generate* new markdown content → that's a content task, not a preview task.
- Source is not markdown (`.tex`, `.rst`, `.docx`) → use pandoc directly or a different skill.
- Han wants live-reload in the browser → use `md-preview <file> --watch` from his shell directly; this skill issues a one-shot render.

## Workflow

### Step 1: Resolve the file path

Han may pass:

- An absolute path (`/Users/tieubao/workspace/.../Day-04-explained.md`) — use as-is.
- A repo-relative path (`learning/quantum-computing/courses/qworld-oqi/Day-04-explained.md`) — resolve against the current cwd (or against `~/workspace/tieubao/ops-toolkit/` when in that repo).
- A partial filename (`Day-04-explained`, `Day-04-explained.md`) — search the current repo for a matching file. If 0 matches: ask. If >1 match: list them and ask which.

If nothing was pointed at, ask Han for the path. Don't guess.

### Step 2: Sanity-check the file

```bash
test -f "<path>" || echo "MISSING"
```

If missing, surface the error to Han and stop. If not a `.md` or `.markdown` file, warn but proceed (pandoc handles other formats; user knows what they want).

### Step 3: Run `md-preview`

```bash
md-preview "<absolute-or-relative-path>"
```

The Bash tool's stdout is NOT a TTY, so the CLI's TTY-auto-detect kicks in and `--no-open` is implied automatically. Browser is never hijacked.

Capture the **last line of stdout** — that's the absolute path to the rendered HTML file. Anything earlier on stdout is unexpected; report it.

If exit code is non-zero:
- `1` → source file bad (not found / not readable / empty). Surface to Han.
- `2` → pandoc missing or failed. If pandoc missing, tell Han `brew install pandoc`. If pandoc failed, surface its stderr.
- `64` → usage error (shouldn't happen if we constructed the invocation correctly; surface as a bug).
- Other → surface as-is.

### Step 4: Surface the URL

Once you have the output path, format it as a `file://` URL and present it:

```
Rendered: file:///tmp/md-preview/day-04-explained.html
```

Most terminals (iTerm2, Ghostty, Wezterm, Kitty, Warp, Terminal.app) render `file://` URLs as clickable links. Han clicks to open in his default browser.

If Han said something like "and open it" or "show me in browser", also offer to run `open "<path>"` as a follow-up Bash call. Default: don't open unprompted (respects the original `--no-open` discipline).

### Step 5 (optional): --watch mode

If Han said "watch", "live edit", "regenerate on save", or "/md-preview --watch", invoke with `--watch`:

```bash
md-preview "<path>" --watch
```

This blocks the Bash tool call until Han Ctrl-Cs the watch. Probably better to tell Han the command and let him run it himself in his own terminal, since holding open a long-running Bash call in Claude Code is awkward. Suggested response:

> "For live-edit mode, run this in your terminal directly:
> 
> ```bash
> md-preview <path> --watch
> ```
> 
> It will render once, open the file:// path, then re-render on every save. Ctrl-C to stop."

## Examples

### Han: "render Day-04-explained.md"

1. Search for matches; find `learning/quantum-computing/courses/qworld-oqi/Day-04-explained.md`.
2. Run `md-preview learning/quantum-computing/courses/qworld-oqi/Day-04-explained.md`.
3. Capture stdout: `/tmp/md-preview/day-04-explained.html`.
4. Surface: `Rendered: file:///tmp/md-preview/day-04-explained.html`.

### Han: "preview the explained doc and open it"

1. Same resolve + render as above.
2. After surfacing the URL, run `open "/tmp/md-preview/day-04-explained.html"` via Bash.
3. Confirm: `Opened in default browser.`

### Han: "render foo.md into ~/Desktop/preview.html"

1. Run `md-preview foo.md --out ~/Desktop/preview.html`.
2. Capture stdout, surface URL.

### Han: "preview /tmp/notes.md with watch"

1. Don't run the watch yourself (would block).
2. Surface the command for Han to run in his terminal:
   ```
   md-preview /tmp/notes.md --watch
   ```

## Anti-patterns

- **Running with `open` by default**: `md-preview` auto-detects TTY and respects it. Don't pass `--no-open` redundantly, and don't `open` the file unless Han asked.
- **Holding open a `--watch` Bash call**: blocks the Claude Code Bash tool indefinitely. Always defer watch mode to Han's own terminal.
- **Guessing the file path**: if multiple matches or no matches, ask. Wrong renders waste time.
- **Re-implementing the renderer**: this skill is a thin wrapper over the CLI. Don't try to call pandoc directly.

## Dependencies

- `md-preview` CLI must be on PATH. Verify with `which md-preview`. If missing, the tool lives at `~/workspace/tieubao/ops-toolkit/tools/md-preview/`; symlink with `ln -sfv ~/workspace/tieubao/ops-toolkit/tools/md-preview/bin/md-preview ~/.local/bin/md-preview`.
- `pandoc` and (for watch mode) `entr` must be installed. The CLI's `--version` flag reports both.

## See also

- Tool: `~/workspace/tieubao/ops-toolkit/tools/md-preview/`
- Contract: `tools/md-preview/SPEC.md` (12 acceptance criteria the CLI satisfies)
- Sister skills: `learning-day-process` (produces math-heavy `.md` files that benefit from this preview), `concept-explain` (single-concept Q&A; usually short enough not to need a preview).
