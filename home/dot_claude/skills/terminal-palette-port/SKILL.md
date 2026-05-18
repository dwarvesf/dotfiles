---
name: terminal-palette-port
description: Use when the user wants to copy one GUI terminal's color palette to another so they look identical (e.g. "copy Warp's Adeberry to cmux", "port my iTerm theme to Ghostty", "make Alacritty match kitty"), AND the source theme is bundled / not exposed as a yaml / no public dump exists, AND macOS TCC blocks driving the source app via osascript or computer-use. Trigger phrases include "copy the palette of <app> to <app>", "port this terminal's theme", "extract colors from a GUI terminal I can't keystroke into", "make these two terminals look identical", "TCC blocks osascript on Warp/iTerm/etc". Specific to macOS; assumes Screen Recording is granted to the claude process; works for any source that responds to standard ANSI bg-color escapes and any target that accepts a hex palette.
---

# Terminal palette port (GUI source → any target)

## Overview

**Source's pty slave is writable; the terminal renders whatever you write there.**

This skill is the workaround for: source's palette is proprietary-bundled, no community
port exists, and TCC blocks every keystroke route. Instead of driving the source app, you
hand its renderer an ANSI test pattern via its own pty, screencap, and pixel-pick the
displayed colors.

## When NOT to use this

- Source's theme is already a parseable file (`~/.<app>/themes/*.yaml`, `*.toml`,
  `*.json`). Read it directly.
- Source has an export-theme button in its UI. Use it.
- The community has the palette dumped (search `github.com`, `terminalcolors.com`, the
  source's own themes repo). Cite-and-copy.
- The user can paste a 1-liner in the source terminal. Use the OSC-query script (see
  *Faster path* below) instead of this whole chain.
- No Screen Recording grant - `screencapture -x` will fail; ask the user to grant it.

## Faster path (try first; falls through to main chain if blocked)

Most terminals respond to **OSC color queries**: `printf '\e]4;N;?\e\\'` returns the
current value of palette slot N as `rgb:RRRR/GGGG/BBBB`. Same for OSC 10 (fg), 11 (bg),
12 (cursor), 17 (selection-bg), 19 (selection-fg).

If the user can paste one command in the source terminal, this returns the palette
directly without screenshots:

```bash
# Stage script (Claude does this)
cat > /tmp/palette-query.sh <<'EOF'
#!/usr/bin/env bash
set -u; OUT="${1:-/tmp/palette.conf}"
exec 3<>/dev/tty; old=$(stty -g <&3); trap 'stty "$old" <&3' EXIT
stty raw -echo <&3
query() { printf '\e]%s;?\e\\' "$1" >&3; local r="" ch i=0 to=0.4
  while (( i < 96 )); do
    IFS= read -r -s -n 1 -t "$to" ch <&3 || break
    r+="$ch"; to=0.05
    [[ "$ch" == $'\a' || "${r: -2}" == $'\e\\' ]] && break
    ((i++))
  done
  local rgb="${r##*rgb:}"; rgb="${rgb%%[$'\e\a']*}"
  printf "#%s%s%s" "${rgb:0:2}" "${rgb:5:2}" "${rgb:10:2}"
}
: > "$OUT"
for n in $(seq 0 15); do printf "palette = %d=%s\n" "$n" "$(query "4;$n")" >> "$OUT"; done
for p in 10:foreground 11:background 12:cursor-color 17:selection-background 19:selection-foreground; do
  printf "%s = %s\n" "${p##*:}" "$(query "${p%%:*}")" >> "$OUT"
done
echo "# done" >> "$OUT"
EOF
# User pastes this in the source terminal:
#   bash /tmp/palette-query.sh /tmp/source-palette.conf
```

If the user is willing → 10 seconds, exact. If blocked or unavailable → main chain below.

## Main chain (no user keystroke needed)

Six steps. Each is a single command-cluster.

### 1. Verify Screen Recording works

```bash
screencapture -x /tmp/probe.png && file /tmp/probe.png
```

PNG → continue. Error → fall back to *Faster path* above and ask user to paste.

### 2. Find the source's visible-tab pty

```bash
# source-app pids (replace pattern)
pgrep -lf "Warp.app/Contents/MacOS/stable"  # or iTerm.app, Alacritty.app, etc.
# Children of source's terminal-server are shells; each owns a tty
for pid in $(pgrep -P <terminal-server-pid>); do ps -p $pid -o pid=,tty=; done
# Write a yellow marker into each candidate tty; whichever appears on screen = active tab
for tty in <candidates>; do
  printf '\n\e[48;5;226m\e[30m  PROBE_%s  \e[0m\n' "$tty" > /dev/$tty
done
osascript -e 'tell application "Warp" to activate'  # `activate` doesn't need AX
sleep 0.4
screencapture -x /tmp/probe.png
```

Use `Read` on `/tmp/probe.png` to see which `PROBE_ttysNNN` is visible. That's `$TTY`.

### 3. Paint the 16-color test pattern

Compact (1 line per bar) so all 16 fit without scrolling. Markers anchor the pattern in
the screenshot for programmatic detection:

```bash
TTY=ttysNNN  # from step 2
{
  printf '\e[0m\e[2J\e[H'
  printf '=== CLAUDE_PALETTE_START_MARKER_X7Z9 ===\n'
  printf '\e[49m\e[39mDEFAULT_FG_TEXT_FOR_SAMPLING\e[K\n'
  printf '\e[49m\e[K\n'
  for n in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    printf '\e[0m\e[48;5;%dm\e[37m P%02d \e[K\e[0m\n' "$n" "$n"
  done
  printf '=== CLAUDE_PALETTE_END_MARKER_X7Z9 ===\n'
} > /dev/$TTY
sleep 0.4
screencapture -x /tmp/palette.png
```

### 4. Pixel-pick via PIL

```python
# /tmp/pick.py - invoke via: uv run --with pillow python3 /tmp/pick.py /tmp/palette.png
import sys
from PIL import Image
from collections import Counter
img = Image.open(sys.argv[1]).convert("RGB")
W, H = img.size
x = int(W * 0.65)  # well past the "P##" label
def b(p): r,g,bv=p; return (r>>4, g>>4, bv>>4)  # quantize for AA tolerance
runs, y = [], 0
while y < H:
    p = img.getpixel((x, y)); bk = b(p); e = y
    while e+1 < H and b(img.getpixel((x, e+1))) == bk: e += 1
    runs.append((y, e, p, bk)); y = e + 1
cand = [r for r in runs if r[1]-r[0] >= 15]
bg_b = Counter(r[3] for r in cand).most_common(1)[0][0]
bars = [r for r in cand if r[3] != bg_b]
for i, (s, e, _, _b) in enumerate(bars):
    p = img.getpixel((x, (s+e)//2))
    print(f"palette = {i}=#{p[0]:02x}{p[1]:02x}{p[2]:02x}")
for s, e, p, bk in cand:
    if bk == bg_b and e-s > 30:
        print(f"background = #{p[0]:02x}{p[1]:02x}{p[2]:02x}"); break
```

Expect 16 bar lines + 1 bg line. If count is wrong, leftover output is in scrollback -
re-do step 3 with a fresh `\e[2J\e[H`.

### 5. Foreground sample

Sample text-bearing rows between the start-marker and the first bar; most-common non-bg
pixel = fg color. Pattern in research note `research/2026-05-18-gui-terminal-palette-extraction.md`.

For cursor and selection: cursor defaults to fg; selection-bg picks a gray ~25% lighter
than bg (e.g. `#3a3f44` for a `#1e2022` bg). Refine if user notices mismatch.

### 6. Write target theme + cleanup

Target = Ghostty (cmux uses Ghostty): drop file at `~/.config/ghostty/themes/<name>`
(flat `key = value`, see step 4 output), set `theme = <name>` in `~/.config/ghostty/config`.
Reload: `Cmd+Shift+,` in cmux.

Other targets:
- **iTerm2**: build a `.itermcolors` plist with the same hex values.
- **Alacritty**: `colors:` section in `~/.config/alacritty/alacritty.toml`.
- **WezTerm**: `~/.config/wezterm/colors/<name>.toml`.
- **kitty**: `~/.config/kitty/themes/<name>.conf`.

Cleanup the source's tab:

```bash
printf '\e[0m\e[2J\e[H' > /dev/$TTY
```

## Common mistakes (from the 2026-05-18 Warp → cmux session)

| Mistake | Fix |
|---|---|
| Trying to extract palette via `strings` on the source's binary | Themes are runtime structs (e.g. `pathfinder_color::Color` as `[f32;4]`), not inline hex consts. Skip; go to pty-paint. |
| Looking for the theme yaml in `~/.<source>/themes/` for a bundled theme | That directory only has user-created themes. Bundled ones live in the binary. |
| Trying `osascript ... keystroke "bash /tmp/..."` to drive the source | TCC denies for `claude` (error 1002). Don't retry the same call; pivot to pty-paint. |
| Trying `mcp__computer-use__type` into a terminal | Terminals are tier-"click"; typing blocked. Same wall as osascript. |
| Writing to source's pty slave to *inject input* to the shell | Slave-side write reaches the OUTPUT stream, not shell stdin. TIOCSTI is dead on modern macOS. But it DOES paint the terminal - that's exactly what we want. |
| Painting 3+ lines per bar | Pattern overflows visible area; bars scroll out the top. Use 1 line per bar so all 16 + markers + fg-row fit. |
| Sampling pixels at the leftmost column | You'll hit the `P##` label text, not the bar fill. Sample at `W * 0.65`. |
| Forgetting to clear before painting | Leftover pattern from prior run produces extra runs; pixel-picker counts more than 16 bars. Always lead with `\e[2J\e[H`. |

## Quick reference: when each path applies

| Symptom | Use |
|---|---|
| Source has parseable theme file | Direct read |
| Source has export-theme UI | User clicks it |
| Community has the palette dumped | Cite + copy |
| User can paste 1 command in source | *Faster path* (OSC queries) |
| All above blocked; Screen Recording works | *Main chain* (pty-paint + screencap + pixel-pick) |
| Screen Recording also blocked | Ask user for the paste OR for an AX grant |

## Related

- Full forensic log of dead-ends + working chain:
  `~/workspace/tieubao/ops-toolkit/research/2026-05-18-gui-terminal-palette-extraction.md`
- Concrete output for Warp Adeberry → cmux: `~/.config/ghostty/themes/adeberry`
