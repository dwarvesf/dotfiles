#!/usr/bin/env bash
# em-dash-guard.sh - Stop hook that blocks if the last assistant
# message contains a U+2014 em-dash outside of fenced code blocks
# and inline code spans. Han's hard rule: "NEVER use em dashes."
# The habit slips under load; this catches and forces a rewrite.
#
# Exclusions:
#   - Inside fenced code blocks (```...```): allowed, often quoting
#     the symbol from a rule statement or pasting third-party text.
#   - Inside inline code spans (`...`): same reason.
#
# Hook protocol: stdin = JSON with at least:
#   {"transcript_path": "/path/to/.../sessions.jsonl", "session_id": "..."}
# Output:
#   - exit 0 if clean
#   - exit 2 with stderr message to BLOCK stop and force rewrite
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

LAST_TEXT=$(jq -rs '
    map(select(.type == "assistant"))
    | last
    | .message.content
    | (if type == "array"
       then map(select(.type == "text") | .text) | join("\n")
       else (. // "")
       end)
' "$TRANSCRIPT" 2>/dev/null)

[ -z "$LAST_TEXT" ] && exit 0

# Strip fenced code blocks and inline code spans before testing.
STRIPPED=$(printf '%s' "$LAST_TEXT" | python3 -c '
import re, sys
text = sys.stdin.read()
text = re.sub(r"```[\s\S]*?```", "", text)
text = re.sub(r"`[^`\n]+`", "", text)
sys.stdout.write(text)
' 2>/dev/null)

if printf '%s' "$STRIPPED" | grep -q '—'; then
    printf '[%s] [STYLE-EM-DASH] [%s] last assistant message contains em-dash\n' \
        "$(date -u +%FT%TZ)" "$SESSION_ID" >>"$LOG" 2>/dev/null
    {
        echo "============= BLOCKED: em-dash in your last response ============="
        echo
        echo "Han's hard rule: NEVER use em dashes (—, U+2014) in responses."
        echo "Replace each with: comma (,), colon (:), semicolon (;),"
        echo "parentheses (), or a sentence break (.). Hyphens (-) and en"
        echo "dashes (–) are fine."
        echo
        echo "Re-emit a corrected version of the response with every em-dash"
        echo "removed. Do not stop until this hook clears."
        echo "=================================================================="
    } >&2
    exit 2
fi

exit 0
