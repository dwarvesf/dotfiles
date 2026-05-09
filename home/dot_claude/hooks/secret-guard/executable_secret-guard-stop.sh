#!/usr/bin/env bash
# secret-guard-stop.sh - Claude Code Stop hook companion to
# secret-guard.sh.
#
# When Claude finishes a turn, scan the last assistant message in
# the transcript for known credential patterns. If found, log to the
# audit log and emit a warning to stderr. Detection-only: by the time
# Stop fires, the message is already on disk; the warning gives the
# user a chance to rotate the leaked credential.
#
# Hook protocol: stdin = JSON with at least:
#   {"transcript_path": "/path/to/.../sessions.jsonl",
#    "session_id": "..."}
# Output: exit 0 (always allow stop). Could exit 2 to ask Claude to
# retry without the leak, but that risks loops if Claude can't
# self-correct; warn-only is safer.
#
# Audit log entries:
#   [<UTC ts>] [STOP-LEAK] [<session>] [stop] message N matched: <pattern-name>
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
echo "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

PATTERNS="${HOME}/.claude/hooks/patterns/secrets.json"
[ ! -f "$PATTERNS" ] && exit 0

LOG="${HOME}/.cache/claude-secret-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Pull the LAST assistant message text from the JSONL. Each line is
# a JSON object; assistant messages have type=="assistant". The
# `message.content` is an array of content blocks; we want the text
# of the text-typed blocks concatenated.
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

HIT=$(jq -rn --arg p "$LAST_TEXT" --slurpfile pats "$PATTERNS" '
    $pats[0] | map(select(.r as $r | $p | test($r))) | map(.n) | .[0] // empty
' 2>/dev/null)

if [ -n "$HIT" ]; then
    printf '[%s] [STOP-LEAK] [%s] [stop] last assistant message matched: %s\n' \
        "$(date -u +%FT%TZ)" "$SESSION_ID" "$HIT" >>"$LOG" 2>/dev/null
    {
        echo "============= WARNING: secret pattern in response (S-62) ============="
        echo "Claude's last message contains a string matching: $HIT"
        echo
        echo "The message is already in the session transcript at:"
        echo "  $TRANSCRIPT"
        echo
        echo "If the matched string is a real credential:"
        echo "  1. Rotate it on the upstream service NOW."
        echo "  2. The transcript JSONL persists on disk; consider deleting it."
        echo
        echo "If it is a false positive (commit SHA, hash, identifier, fixture),"
        echo "ignore. Audit-log entry: ~/.cache/claude-secret-guard.log"
        echo "======================================================================"
    } >&2
fi

exit 0
