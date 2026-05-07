#!/usr/bin/env bash
# Claude Code statusLine  - Catppuccin Mocha palette
input=$(cat)

# Catppuccin Mocha colors
BLUE='\033[38;2;137;180;250m'    # blue
GREEN='\033[38;2;166;227;161m'   # green
YELLOW='\033[38;2;249;226;175m'  # yellow
RED='\033[38;2;243;139;168m'     # red
MAUVE='\033[38;2;203;166;247m'   # mauve
SAPPHIRE='\033[38;2;116;199;236m' # sapphire (5h low)
PEACH='\033[38;2;250;179;135m'   # peach (7d warn)
DIM='\033[38;2;108;112;134m'     # overlay0
RESET='\033[0m'

# --- Directory ---
cwd=$(echo "$input" | jq -r '.cwd // empty')
if [ -n "$cwd" ]; then
  cwd="${cwd/#$HOME/\~}"
  count=$(echo "$cwd" | tr '/' '\n' | grep -c -v '^$')
  if [ "$count" -gt 3 ]; then
    dir="…/$(echo "$cwd" | rev | cut -d'/' -f1-3 | rev)"
  else
    dir="$cwd"
  fi
else
  dir="?"
fi

# --- Git ---
git_part=""
real_cwd=$(echo "$input" | jq -r '.cwd // empty')
if git -C "$real_cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$real_cwd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$real_cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    flags=""
    porcelain=$(git -C "$real_cwd" status --porcelain 2>/dev/null)
    echo "$porcelain" | grep -q '^?? '       && flags="${flags}?"
    echo "$porcelain" | grep -q '^ M\|^M '   && flags="${flags}!"
    echo "$porcelain" | grep -q '^A \|^M '    && flags="${flags}+"
    ahead=$(git -C "$real_cwd" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
    behind=$(git -C "$real_cwd" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ')
    [ "$ahead" -gt 0 ] 2>/dev/null  && flags="${flags}⇡"
    [ "$behind" -gt 0 ] 2>/dev/null && flags="${flags}⇣"
    if [ -n "$flags" ]; then
      git_part=" ${GREEN} ${branch}${RESET} ${YELLOW}[${flags}]${RESET}"
    else
      git_part=" ${GREEN} ${branch}${RESET}"
    fi
  fi
fi

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // .model // empty')
# If it's still a JSON object, extract display_name
if echo "$model" | grep -q '^{'; then
  model=$(echo "$model" | jq -r '.display_name // .id // empty')
fi
[ -n "$model" ] && model_part=" ${DIM}│${RESET} ${MAUVE}${model}${RESET}" || model_part=""

# --- Reasoning effort ---
effort_part=""
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  case "$effort" in
    low)    e_letter="L";   e_color="$DIM" ;;
    medium) e_letter="M";   e_color="$SAPPHIRE" ;;
    high)   e_letter="H";   e_color="$PEACH" ;;
    xhigh)  e_letter="X";   e_color="$RED" ;;
    max)    e_letter="MAX"; e_color="$RED" ;;
    *)      e_letter="$effort"; e_color="$DIM" ;;
  esac
  effort_part=" ${e_color}[${e_letter}]${RESET}"
fi

# --- Context ---
ctx_part=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    color="$RED"
  elif [ "$used_int" -ge 50 ]; then
    color="$YELLOW"
  else
    color="$GREEN"
  fi
  ctx_part=" ${DIM}│${RESET} ${color}${used_int}%${RESET}"
fi

# --- Rate limit reset countdown helper ---
fmt_remaining() {
  local resets_at=$1
  local now d h m remaining
  now=$(date +%s)
  remaining=$((resets_at - now))
  [ "$remaining" -le 0 ] && return
  d=$((remaining / 86400))
  h=$(((remaining % 86400) / 3600))
  m=$(((remaining % 3600) / 60))
  if [ "$d" -gt 0 ]; then
    printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then
    printf '%dh%02dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# --- Rate limit ---
rate_part=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_pct" ]; then
  five_int=$(printf '%.0f' "$five_pct")
  if [ "$five_int" -ge 80 ]; then
    color="$RED"
  elif [ "$five_int" -ge 50 ]; then
    color="$YELLOW"
  else
    color="$SAPPHIRE"
  fi
  five_eta=""
  five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  if [ -n "$five_resets" ]; then
    eta=$(fmt_remaining "$five_resets")
    [ -n "$eta" ] && five_eta=" ${DIM}${eta}${RESET}"
  fi
  rate_part=" ${color}5h:${five_int}%${RESET}${five_eta}"
fi

# --- Weekly rate limit ---
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$seven_pct" ]; then
  seven_int=$(printf '%.0f' "$seven_pct")
  if [ "$seven_int" -ge 80 ]; then
    color="$RED"
  elif [ "$seven_int" -ge 50 ]; then
    color="$PEACH"
  else
    color="$MAUVE"
  fi
  seven_eta=""
  seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  if [ -n "$seven_resets" ]; then
    eta=$(fmt_remaining "$seven_resets")
    [ -n "$eta" ] && seven_eta=" ${DIM}${eta}${RESET}"
  fi
  rate_part="${rate_part} ${color}7d:${seven_int}%${RESET}${seven_eta}"
fi

# --- Session duration ---
duration_part=""
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  duration_sec=$((duration_ms / 1000))
  hours=$((duration_sec / 3600))
  mins=$(( (duration_sec % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    duration_part=" ${DIM}${hours}h${mins}m${RESET}"
  elif [ "$mins" -gt 0 ]; then
    duration_part=" ${DIM}${mins}m${RESET}"
  fi
fi

# --- Hostname ---
host=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
[ -n "$host" ] && host_part=" ${DIM}@${host}${RESET}" || host_part=""

printf '%b' "${BLUE}${dir}${RESET}${git_part}${model_part}${effort_part}${ctx_part}${rate_part}${duration_part}${host_part}"
