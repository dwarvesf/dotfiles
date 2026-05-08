#!/usr/bin/env bash
# Claude Code statusLine - Catppuccin Mocha.
# Uses only powerline branch () + plain Unicode glyphs;
# avoids Material Design / FontAwesome NerdFont icons that
# don't render in this terminal's font.
input=$(cat)

# Catppuccin Mocha colors
BLUE='\033[38;2;137;180;250m'
GREEN='\033[38;2;166;227;161m'
YELLOW='\033[38;2;249;226;175m'
RED='\033[38;2;243;139;168m'
MAUVE='\033[38;2;203;166;247m'
SAPPHIRE='\033[38;2;116;199;236m'
PEACH='\033[38;2;250;179;135m'
DIM='\033[38;2;108;112;134m'
RESET='\033[0m'

# Abbreviate path: first char of each parent, full leaf.
# /Users/tieubao/workspace/tieubao/ops-toolkit -> w/t/ops-toolkit
# /Users/tieubao/.claude/projects/abc          -> .c/p/abc
# /etc/nginx                                    -> /e/nginx
abbrev_path() {
  local p="$1"
  [ -z "$p" ] && { echo "?"; return; }

  local leading=""
  if [ "$p" = "$HOME" ]; then
    echo "~"; return
  elif [[ "$p" == "$HOME/"* ]]; then
    p="${p#$HOME/}"
  elif [ "$p" = "/" ]; then
    echo "/"; return
  else
    p="${p#/}"
    leading="/"
  fi

  IFS='/' read -ra parts <<< "$p"
  local n=${#parts[@]}
  if [ "$n" -le 1 ]; then
    echo "${leading}${p}"
    return
  fi

  local result="" i first seg
  for ((i=0; i<n-1; i++)); do
    seg="${parts[i]}"
    first="${seg:0:1}"
    # Preserve dot prefix for hidden dirs (.claude -> .c, not .)
    if [ "$first" = "." ] && [ "${#seg}" -gt 1 ]; then
      first="${seg:0:2}"
    fi
    result="${result}${first}/"
  done
  result="${result}${parts[n-1]}"
  echo "${leading}${result}"
}

# Join non-empty args with a separator. Skips empties.
join_by() {
  local sep="$1"; shift
  local first=1 out=""
  for x in "$@"; do
    [ -z "$x" ] && continue
    if [ $first -eq 1 ]; then
      out="$x"; first=0
    else
      out="${out}${sep}${x}"
    fi
  done
  printf '%s' "$out"
}

cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(abbrev_path "$cwd")

# --- Git (keep powerline branch , it renders) ---
git_part=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    flags=""
    porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
    echo "$porcelain" | grep -q '^?? '       && flags="${flags}?"
    echo "$porcelain" | grep -q '^ M\|^M '   && flags="${flags}!"
    echo "$porcelain" | grep -q '^A \|^M '    && flags="${flags}+"
    ahead=$(git -C "$cwd" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
    behind=$(git -C "$cwd" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ')
    [ "$ahead" -gt 0 ] 2>/dev/null  && flags="${flags}⇡"
    [ "$behind" -gt 0 ] 2>/dev/null && flags="${flags}⇣"
    if [ -n "$flags" ]; then
      git_part="  ${GREEN} ${branch}${RESET} ${YELLOW}[${flags}]${RESET}"
    else
      git_part="  ${GREEN} ${branch}${RESET}"
    fi
  fi
fi

# --- Model (strip trailing parenthetical like "(1M context)") ---
model=$(echo "$input" | jq -r '.model.display_name // .model // empty')
if echo "$model" | grep -q '^{'; then
  model=$(echo "$model" | jq -r '.display_name // .id // empty')
fi
model=$(echo "$model" | sed -E 's/[[:space:]]*\([^)]*\)[[:space:]]*$//')
[ -n "$model" ] && model_part="${MAUVE}✦ ${model}${RESET}" || model_part=""

# --- Effort: word only, color-coded ---
effort_part=""
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  case "$effort" in
    low)    e_word="low";  e_color="$DIM" ;;
    medium) e_word="med";  e_color="$SAPPHIRE" ;;
    high)   e_word="high"; e_color="$PEACH" ;;
    xhigh)  e_word="MAX";  e_color="$RED" ;;
    max)    e_word="MAX+"; e_color="$RED" ;;
    *)      e_word="$effort"; e_color="$DIM" ;;
  esac
  effort_part="${e_color}${e_word}${RESET}"
fi

# --- Context % ---
ctx_part=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if   [ "$used_int" -ge 80 ]; then color="$RED"
  elif [ "$used_int" -ge 50 ]; then color="$YELLOW"
  else                              color="$GREEN"
  fi
  ctx_part="${color}${used_int}%${RESET}"
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
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else                      printf '%dm' "$m"
  fi
}

# --- 5h rate limit ---
rate5_part=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_pct" ]; then
  five_int=$(printf '%.0f' "$five_pct")
  if   [ "$five_int" -ge 80 ]; then color="$RED"
  elif [ "$five_int" -ge 50 ]; then color="$YELLOW"
  else                              color="$SAPPHIRE"
  fi
  five_eta=""
  five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  if [ -n "$five_resets" ]; then
    eta=$(fmt_remaining "$five_resets")
    [ -n "$eta" ] && five_eta=" ${DIM}${eta}${RESET}"
  fi
  rate5_part="${color}${five_int}%${RESET}${five_eta}"
fi

# --- 7d rate limit ---
rate7_part=""
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$seven_pct" ]; then
  seven_int=$(printf '%.0f' "$seven_pct")
  if   [ "$seven_int" -ge 80 ]; then color="$RED"
  elif [ "$seven_int" -ge 50 ]; then color="$PEACH"
  else                              color="$MAUVE"
  fi
  seven_eta=""
  seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  if [ -n "$seven_resets" ]; then
    eta=$(fmt_remaining "$seven_resets")
    [ -n "$eta" ] && seven_eta=" ${DIM}${eta}${RESET}"
  fi
  rate7_part="${color}${seven_int}%${RESET}${seven_eta}"
fi

# --- Hostname ---
host=$(hostname -s 2>/dev/null)
[ -n "$host" ] && host_part="${DIM}${host}${RESET}" || host_part=""

# --- Assemble (2-line: identity / budget) ---
# Line 1: path + git + model + effort  (identity)
line1="${BLUE}${dir}${RESET}${git_part}"
[ -n "$model_part" ]  && line1="${line1}  ${model_part}"
[ -n "$effort_part" ] && line1="${line1} ${effort_part}"

# Line 2: ctx + 5h + 7d + host  (budget, bullet-separated)
SEP="  ${DIM}·${RESET}  "
line2=$(join_by "$SEP" "$ctx_part" "$rate5_part" "$rate7_part" "$host_part")

out="$line1"
[ -n "$line2" ] && out="${out}\n${line2}"

printf '%b' "$out"
