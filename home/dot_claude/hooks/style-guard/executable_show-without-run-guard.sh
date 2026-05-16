#!/usr/bin/env bash
# show-without-run-guard.sh - Stop hook that blocks if the assistant's
# current turn includes a fenced ```bash``` (or sh/zsh/shell) code block
# in text output but did not make ANY tool calls during the turn.
#
# Catches the "here are the commands you can run, want me to proceed?"
# sycophancy pattern. Per Han's rule: run AND show, never show without
# running. If something genuinely blocks execution, name the blocker
# instead of dropping a preview and stalling.
#
# Detection window:
#   from the last user message forward, look at all assistant messages
#   in the current turn. Concatenate their text. Count tool_use blocks
#   of ANY kind (Bash, Edit, Write, MultiEdit, etc.).
#
# Block when:
#   - text contains a fenced ```bash | sh | zsh | shell``` block
#   - AND zero tool_use blocks in the turn
#
# Allow when:
#   - Claude made any tool call (it did SOMETHING, not just preview)
#   - Or no bash code block in text
#
# Hook protocol: stdin = JSON with transcript_path + session_id.
# Output: exit 0 (clean) or exit 2 (block with stderr message).
#
# Audit log: ~/.cache/claude-style-guard.log
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
echo "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

LOG="${HOME}/.cache/claude-style-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

ANALYSIS=$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null
import json, re, sys
path = sys.argv[1]
msgs = []
with open(path) as f:
    for line in f:
        try:
            msgs.append(json.loads(line))
        except Exception:
            pass

# Find the start of the current turn (just after the last user message).
boundary = 0
for i in range(len(msgs) - 1, -1, -1):
    if msgs[i].get("type") == "user":
        boundary = i + 1
        break

turn = msgs[boundary:]
text_parts = []
tool_uses = 0

for m in turn:
    if m.get("type") != "assistant":
        continue
    content = m.get("message", {}).get("content", [])
    if not isinstance(content, list):
        continue
    for part in content:
        if not isinstance(part, dict):
            continue
        t = part.get("type")
        if t == "text":
            text_parts.append(part.get("text", ""))
        elif t == "tool_use":
            tool_uses += 1

text = "\n".join(text_parts)
bash_blocks = re.findall(r"```(?:bash|sh|zsh|shell)\b[\s\S]*?```", text)

if bash_blocks and tool_uses == 0:
    print("BLOCK")
    preview = bash_blocks[0][:240]
    print(preview)
PY
)

if printf '%s' "$ANALYSIS" | head -1 | grep -q "^BLOCK$"; then
    PREVIEW=$(printf '%s' "$ANALYSIS" | tail -n +2)
    printf '[%s] [STYLE-SHOW-NO-RUN] [%s] bash block emitted, no tool calls\n' \
        "$(date -u +%FT%TZ)" "$SESSION_ID" >>"$LOG" 2>/dev/null
    {
        echo "============= BLOCKED: command shown but not run ============="
        echo
        echo "Your turn includes a fenced bash code block but you made zero"
        echo "tool calls. Han's rule: explain AND do, not show AND wait."
        echo
        echo "Three valid responses to this block:"
        echo "  (a) Run the command via the Bash tool now, then stop."
        echo "  (b) If the command must execute on a machine you cannot"
        echo "      reach from here (iPhone, someone else's box), say so"
        echo "      explicitly in text (e.g. 'on your iPhone, run:')."
        echo "  (c) If the block is documentation (runbook entry, README),"
        echo "      say so explicitly (e.g. 'add to your runbook:')."
        echo
        echo "First fenced bash block (preview):"
        echo "$PREVIEW"
        echo
        echo "==============================================================="
    } >&2
    exit 2
fi

exit 0
