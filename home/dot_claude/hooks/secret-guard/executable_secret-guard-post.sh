#!/usr/bin/env bash
# secret-guard-post.sh - Claude Code PostToolUse hook companion to
# secret-guard.sh.
#
# After any tool call, scan the tool_response for known credential
# patterns. If found, log to the audit log and emit a warning to
# stderr. Catches the leak surface PreToolUse cannot see:
#   - Read of an unlisted path that contains a credential
#   - Bash command whose stdout legitimately echoes a token (API
#     responses, debug output)
#   - MCP / WebFetch / other tool results we don't pre-filter
#
# Detection-only by design: modifying tool_response is non-portable
# across Claude Code versions and would silently swallow real output.
# A loud warning + audit-log entry is enough to prompt the user to
# rotate the credential and (if needed) delete the transcript.
#
# Hook protocol: stdin = JSON with at least:
#   {"session_id": "...", "tool_name": "Bash"|"Read"|...,
#    "tool_input": {...}, "tool_response": {...}}
# Output: exit 0 always.
#
# Audit log entries:
#   [<UTC ts>] [POST-LEAK] [<session>] [<tool>] response matched: <pattern-name>
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
echo "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

PATTERNS="${HOME}/.claude/hooks/patterns/secrets.json"
[ ! -f "$PATTERNS" ] && exit 0

LOG="${HOME}/.cache/claude-secret-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"')

# Extract a single string from tool_response. Different tools emit
# different shapes; coerce all of them to a flat string for scanning.
RESPONSE=$(printf '%s' "$INPUT" | jq -r '
    .tool_response
    | if type == "string" then .
      elif type == "object" then
        # Common shapes: { content: "..." }, { content: [{type:"text",text:"..."}, ...] },
        # { stdout, stderr, exit_code }, { text: "..." }, etc.
        [
            (.content // empty
             | if type == "array"
               then (map(select(.type == "text") | .text) | join("\n"))
               else tostring
               end),
            (.stdout // ""),
            (.stderr // ""),
            (.text // ""),
            (.output // "")
        ] | join("\n")
      elif type == "array" then
        map(if type == "object" and .text then .text else tostring end) | join("\n")
      else tostring
      end
' 2>/dev/null)

[ -z "$RESPONSE" ] && exit 0

HIT=$(jq -rn --arg p "$RESPONSE" --slurpfile pats "$PATTERNS" '
    $pats[0] | map(select(.r as $r | $p | test($r))) | map(.n) | .[0] // empty
' 2>/dev/null)

if [ -n "$HIT" ]; then
    printf '[%s] [POST-LEAK] [%s] [%s] response matched: %s\n' \
        "$(date -u +%FT%TZ)" "$SESSION_ID" "$TOOL_NAME" "$HIT" >>"$LOG" 2>/dev/null
    {
        echo "============= WARNING: secret pattern in tool_response (S-62) ============="
        echo "$TOOL_NAME tool returned a string matching: $HIT"
        echo
        echo "The response is now in the session transcript."
        echo
        echo "If the matched string is a real credential:"
        echo "  1. Rotate it on the upstream service NOW."
        echo "  2. Inspect ~/.cache/claude-secret-guard.log for context."
        echo
        echo "If it is a false positive (hash, SHA, identifier), ignore."
        echo "==========================================================================="
    } >&2
fi

exit 0
