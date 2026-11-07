#!/usr/bin/env bash
# Billed and actual GitHub Actions minutes for workflow runs.
# Usage: ci-cost.sh OWNER/REPO RUN_ID [RUN_ID...] [--attempt N]
# Prints one JSON object per run: billed minutes by runner label (each job rounded up to a
# whole minute, as GitHub bills), actual minutes, job count and wall clock. Skipped jobs
# are left out. Needs gh (authenticated) and jq.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 OWNER/REPO RUN_ID [RUN_ID...] [--attempt N]" >&2; exit 2; }
repo=$1; shift
attempt=1 ids=()
while [ $# -gt 0 ]; do
  case $1 in
    --attempt) attempt=$2; shift 2 ;;
    *) ids+=("$1"); shift ;;
  esac
done
for id in "${ids[@]}"; do
  gh api --paginate "repos/$repo/actions/runs/$id/attempts/$attempt/jobs?per_page=100" --jq '.jobs[]' |
    jq -s --arg id "$id" '
      map(select(.started_at and .completed_at and .conclusion != "skipped")
        | . + {secs: ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)),
               runner: ((.labels // [])[0] // "unknown")}) as $j
      | {run: $id,
         jobs: ($j | length),
         wall_min: (if ($j | length) == 0 then 0 else
           ((($j | map(.completed_at | fromdateiso8601) | max)
             - ($j | map(.started_at | fromdateiso8601) | min)) / 60 | floor) end),
         billed_min: ($j | group_by(.runner)
           | map({(.[0].runner): (map(if .secs > 0 then ((.secs + 59) / 60 | floor) else 0 end) | add)}) | add),
         actual_min: ($j | group_by(.runner)
           | map({(.[0].runner): (map(.secs) | add / 6 | floor / 10)}) | add),
         slowest: ($j | sort_by(-.secs) | .[0:5] | map({name, min: (.secs / 6 | floor / 10), runner}))}'
done
