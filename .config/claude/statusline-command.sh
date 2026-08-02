#!/bin/bash
# Claude Code statusline: model, context-window progress, and 5h/7d
# rate-limit reset progress bars, with reset times shown in UK time.

input=$(cat)

# Every field below is parsed with jq. Without it there is nothing to render, so
# bow out quietly rather than printing a broken line on every refresh.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'

model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')

# Renders a 10-cell block-character progress bar for a 0-100 percentage.
bar() {
  local pct="$1" width=10 filled empty i out
  filled=$(awk -v p="$pct" -v w="$width" 'BEGIN{v=int((p/100)*w+0.5); if(v<0)v=0; if(v>w)v=w; print v}')
  empty=$((width - filled))
  out=""
  for ((i = 0; i < filled; i++)); do out+="█"; done
  for ((i = 0; i < empty; i++)); do out+="░"; done
  printf '%s' "$out"
}

# Traffic-light colour for a percentage: green < 50, yellow < 80, red >= 80.
color_for() {
  local pct="$1"
  if awk -v p="$pct" 'BEGIN{exit !(p>=80)}'; then
    printf '%s' "$RED"
  elif awk -v p="$pct" 'BEGIN{exit !(p>=50)}'; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

# Formats a unix epoch (seconds) in UK local time (handles BST/GMT). The weekly
# reset can be days out, so it carries a weekday the five-hour one doesn't need.
# GNU date spells epoch input -d @N, BSD/macOS date spells it -r N.
uk_time() {
  local fmt="+${2:-%H:%M} %Z"
  TZ="Europe/London" date -d "@$1" "$fmt" 2>/dev/null ||
    TZ="Europe/London" date -r "$1" "$fmt" 2>/dev/null
}

SEP="${DIM} │ ${RESET}"

line="${BOLD}${CYAN}${model}${RESET}"

used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  c=$(color_for "$used")
  b=$(bar "$used")
  line="${line}${SEP}Context ${DIM}[${RESET}${c}${b}${RESET}${DIM}]${RESET} ${c}$(printf '%.0f' "$used")%${RESET}"
fi

five_pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
if [ -n "$five_pct" ]; then
  c=$(color_for "$five_pct")
  b=$(bar "$five_pct")
  reset_str=""
  [ -n "$five_reset" ] && reset_str=" ${DIM}resets $(uk_time "$five_reset")${RESET}"
  line="${line}${SEP}5h ${DIM}[${RESET}${c}${b}${RESET}${DIM}]${RESET} ${c}$(printf '%.0f' "$five_pct")%${RESET}${reset_str}"
fi

week_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
if [ -n "$week_pct" ]; then
  c=$(color_for "$week_pct")
  b=$(bar "$week_pct")
  reset_str=""
  [ -n "$week_reset" ] && reset_str=" ${DIM}resets $(uk_time "$week_reset" '%a %H:%M')${RESET}"
  line="${line}${SEP}7d ${DIM}[${RESET}${c}${b}${RESET}${DIM}]${RESET} ${c}$(printf '%.0f' "$week_pct")%${RESET}${reset_str}"
fi

printf '%b\n' "$line"
