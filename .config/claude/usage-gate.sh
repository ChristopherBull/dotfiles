#!/bin/bash
# Exit 0 if there is enough of the 5h window left to start a user story, else 1.
# Reads the cache that statusline-command.sh refreshes on every status update.
# Usage: usage-gate.sh [max-used-percent=80]
max="${1:-80}"
cache="$HOME/.claude/cache/rate-limits.json"
[ -r "$cache" ] || { echo "usage-gate: no rate-limit cache; refusing to start" >&2; exit 1; }
used=$(jq -r '.rate_limits.five_hour.used_percentage // empty' "$cache")
reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' "$cache")
at=$(jq -r '.at // 0 | floor' "$cache")
[ -n "$used" ] || { echo "usage-gate: no 5h figure in cache; refusing to start" >&2; exit 1; }
age=$(( $(date +%s) - at ))
resets=$(TZ=Europe/London date -d "@$reset" +%H:%M 2>/dev/null)
echo "5h window: ${used}% used (cache ${age}s old), resets ${resets:-unknown}, limit ${max}%"
if [ "$age" -gt 900 ]; then echo "usage-gate: figure is stale (>15 min)" >&2; fi
awk -v u="$used" -v m="$max" 'BEGIN{exit !(u<m)}' || { echo "usage-gate: insufficient usage left; do not start a new story" >&2; exit 1; }
