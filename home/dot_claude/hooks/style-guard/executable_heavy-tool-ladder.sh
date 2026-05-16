#!/usr/bin/env bash
# heavy-tool-ladder.sh - PreToolUse hook that fires a ONE-shot-per-
# session-per-category reminder when Claude reaches for a "heavy"
# tool (browser automation or macOS GUI control). Reinforces the
# global CLAUDE.md tool-selection ladders.
#
# Categories:
#   browser    : claude-in-chrome, chrome-devtools, playwright,
#                browserbase (any MCP whose name screams browser)
#   macos-gui  : macos-use (accessibility), peekaboo (vision-loop)
#
# Cloudflare browser navigations get an extra reminder when a CF
# dashboard URL is detected, because the CF Developer Platform MCP
# is almost always the right pick instead.
#
# Behavior: informational only (NOT blocking). Heavy tools CAN be the
# right answer; the goal is to make Claude verify the lighter rungs
# were ruled out before proceeding.
#
# Sentinel files (one per session per category) live in:
#   ~/.cache/claude-tool-ladder/$SESSION_ID-$CATEGORY
# so reminders fire exactly once per category per session.
#
# Hook protocol: stdin = JSON with tool_name + tool_input + session_id.
# Output:
#   first hit per category: emit JSON {"systemMessage": "..."}
#   subsequent hits        : silent
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
echo "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -z "$TOOL" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

CATEGORY=""
case "$TOOL" in
    mcp__claude-in-chrome__*|mcp__chrome-devtools__*)
        CATEGORY="browser"
        ;;
    mcp__playwright*|mcp__plugin_playwright*)
        CATEGORY="browser"
        ;;
    mcp__browserbase*|mcp__plugin_browserbase*)
        CATEGORY="browser"
        ;;
    mcp__macos-use__*|mcp__peekaboo__*)
        CATEGORY="macos-gui"
        ;;
    *)
        exit 0
        ;;
esac

# Also check for Cloudflare-dashboard navigations specifically. These
# get a sharper reminder because the CF MCP almost always replaces
# them.
URL=$(printf '%s' "$INPUT" | jq -r '
    .tool_input.url // .tool_input.value // .tool_input.text // empty
' 2>/dev/null)
CF_DASH=""
if [ "$CATEGORY" = "browser" ] && \
   printf '%s' "$URL" | grep -qiE "(dash|developers|api)\.cloudflare\.com"; then
    CF_DASH="yes"
fi

SENTINEL_DIR="${HOME}/.cache/claude-tool-ladder"
mkdir -p "$SENTINEL_DIR" 2>/dev/null || true
SENTINEL="${SENTINEL_DIR}/${SESSION_ID}-${CATEGORY}"
CF_SENTINEL="${SENTINEL_DIR}/${SESSION_ID}-cloudflare"

# If sentinel exists AND not a CF dashboard hit (or CF sentinel also
# exists), bail silently.
if [ -f "$SENTINEL" ] && { [ -z "$CF_DASH" ] || [ -f "$CF_SENTINEL" ]; }; then
    exit 0
fi

MSG=""
case "$CATEGORY" in
    browser)
        if [ ! -f "$SENTINEL" ]; then
            MSG="REMINDER (once per session): browser automation is the last rung. Per global CLAUDE.md: MCP > CLI (gh, wrangler, op, curl) > browser. Verify an API or CLI does not fit before proceeding. If you do need a browser, /edge-up is Han's default (real Edge profile with logins); /chrome is fallback. Skills: browser-tool-selection, cloudflare-tool-selection."
            touch "$SENTINEL"
        fi
        if [ -n "$CF_DASH" ] && [ ! -f "$CF_SENTINEL" ]; then
            CF_MSG="REMINDER (once per session): you are navigating to a Cloudflare dashboard URL. The CF Developer Platform MCP almost always replaces browser-driven CF work. Try mcp__claude_ai_Cloudflare_Developer_Platform__* (workers, D1, R2, KV, DNS via API token) or 'wrangler' CLI before proceeding. Skill: cloudflare-tool-selection."
            touch "$CF_SENTINEL"
            if [ -n "$MSG" ]; then
                MSG="$MSG  ALSO: $CF_MSG"
            else
                MSG="$CF_MSG"
            fi
        fi
        ;;
    macos-gui)
        if [ ! -f "$SENTINEL" ]; then
            MSG="REMINDER (once per session): macOS GUI control is the heaviest rung. Per global CLAUDE.md: L0 plain CLI (open -a, defaults write, gh, op) > L1 osascript / JXA > L2 'shortcuts run' > L3 macos-use > L4 peekaboo. Confirm L0-L2 do not fit before proceeding. Skill: macos-action-selection."
            touch "$SENTINEL"
        fi
        ;;
esac

if [ -n "$MSG" ]; then
    jq -n --arg m "$MSG" '{"systemMessage": $m}'
fi

exit 0
