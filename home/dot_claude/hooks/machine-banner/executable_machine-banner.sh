#!/usr/bin/env bash
# SessionStart hook: emit "Machine: <user>@<localhostname> (<hw.model>)"
# so Claude Code always knows which physical box this session is on.
# Read by ~/.claude/settings.json -> hooks.SessionStart.
set -eu

USER_NAME=$(whoami)
HOSTNAME=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
MODEL=$(sysctl -n hw.model 2>/dev/null || echo unknown)

printf 'Machine: %s@%s (%s)\n' "$USER_NAME" "$HOSTNAME" "$MODEL"
