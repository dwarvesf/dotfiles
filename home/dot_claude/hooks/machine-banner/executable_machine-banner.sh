#!/usr/bin/env bash
# SessionStart hook: emit machine identity + an explicit DON'T-SSH-HERE rule
# so Claude doesn't misroute (e.g. try to `ssh mac-mini-danang` from a session
# already running ON the Mini).
#
# Read by ~/.claude/settings.json -> hooks.SessionStart.
#
# Output shape is two lines:
#   1. `Machine: <user>@<host> (<hw.model>) [role=<short>]`
#   2. A prescriptive rule line; this turns the banner from a fact Claude
#      may skim into an instruction it has to acknowledge.
#
# Role detection is best-effort by hostname match. Unknown hosts get
# `role=unknown` and a generic rule line (still says "running locally;
# don't ssh to this host").
set -eu

USER_NAME=$(whoami)
HOSTNAME=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
MODEL=$(sysctl -n hw.model 2>/dev/null || echo unknown)

# Role table mirrors ~/.claude/CLAUDE.md "Machines I work from". Keep in sync.
case "$HOSTNAME" in
  Mac-mini|mac-mini|mac-mini-danang)
    ROLE=mini
    ALIASES='mini / mini-tieubao / mac-mini / mac-mini-danang / mini-lan'
    ;;
  Hans-Air-M4|hans-air-m4|mac-air)
    ROLE=air
    ALIASES='air / mac-air / Hans-Air-M4'
    ;;
  trading-egress-tokyo)
    ROLE=trading-egress-tokyo
    ALIASES='egress-tokyo / trading-egress-tokyo'
    ;;
  *)
    ROLE=unknown
    ALIASES="$HOSTNAME"
    ;;
esac

printf 'Machine: %s@%s (%s) [role=%s]\n' "$USER_NAME" "$HOSTNAME" "$MODEL" "$ROLE"
printf 'You are RUNNING ON this host. Do NOT ssh to: %s. Run commands locally. (If unsure mid-session, run `claude-host`.)\n' "$ALIASES"
