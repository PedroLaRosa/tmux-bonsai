#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane='' branch='' desired='done' timeout=600 json=off
while [ "$#" -gt 0 ]; do
 case "$1" in
  --pane|--branch|--for|--timeout)
   [ "$#" -ge 2 ] || { echo "$1 requires a value" >&2; exit 2; }
   case "$1" in --pane) pane=$2;; --branch) branch=$2;; --for) desired=$2;; --timeout) timeout=$2;; esac; shift;;
  --json) json=on;; *) echo "unknown wait option: $1" >&2; exit 2;;
 esac; shift
done
if { [ -z "$pane" ] && [ -z "$branch" ]; } || { [ -n "$pane" ] && [ -n "$branch" ]; }; then
 echo 'usage: bonsai wait --pane ID|--branch BRANCH --for done|waiting|idle|exited [--timeout 600] [--json]' >&2; exit 2
fi
case "$desired" in done|waiting|idle|exited) :;; *) echo "unsupported wait state: $desired" >&2; exit 2;; esac
timeout=$(bonsai_duration "$timeout") || exit 2
start=$SECONDS
while :; do
 if [ -n "$pane" ]; then
  if [ "$desired" = idle ] || [ "$desired" = exited ]; then
   snapshot=$("$BONSAI_SCRIPTS/list.sh" --json --all | jq --arg pane "$pane" '[.[]|select(.pane_id==$pane)]') || exit 1
   if [ "$snapshot" = '[]' ] && [ "$desired" = exited ]; then
    snapshot=$(jq -n --arg pane "$pane" '[{pane_id:$pane,state:"exited"}]')
   fi
  else
  record=$(tmx display-message -p -t "$pane" '#{pane_id} #{@agent_state}' 2>/dev/null) || record="$pane exited"
  read -r id current <<< "$record"
  snapshot=$(jq -n --arg pane "$id" --arg state "$current" '[{pane_id:$pane,state:$state}]')
  fi
 else snapshot=$("$BONSAI_SCRIPTS/list.sh" --json --branch "$branch") || exit 1; fi
 if printf '%s' "$snapshot" | jq -e --arg desired "$desired" 'length>0 and all(.state==$desired or ($desired=="done" and .state=="idle"))' >/dev/null; then
  if [ "$json" = on ]; then printf '%s\n' "$snapshot"; else printf '%s\n' "$snapshot" | jq -r '.[]|"\(.pane_id) \(.state)"'; fi
  exit 0
 fi
 if awk -v elapsed="$((SECONDS-start))" -v timeout="$timeout" 'BEGIN {exit !(elapsed>=timeout)}'; then
  if [ "$json" = on ]; then jq -n --arg state "$desired" --argjson panes "$snapshot" '{error:"timeout",waiting_for:$state,panes:$panes}'
  else echo "bonsai wait: timed out waiting for $desired" >&2; fi
  exit 124
 fi
 sleep 0.2
done
