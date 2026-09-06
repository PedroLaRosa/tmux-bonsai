#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/_lib.sh"

state_init() { mkdir -p "$(bonsai_state_dir)" "$(bonsai_state_dir)/locks"; }

state_set() { # pane key value [key value...]
  local pane=$1 key value; shift
  while [ "$#" -ge 2 ]; do
    key=$1; value=$2; shift 2
    tmx set-option -pq -t "$pane" "@agent_$key" "$value" || return
  done
}

state_log() { # pane event previous state summary decision
  state_init
  local pane=$1 event=$2 previous=$3 state=$4 summary=$5 decision=$6 now
  now=$(date +%s)
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson ts "$now" --arg pane "$pane" --arg event "$event" \
      --arg previous "$previous" --arg state "$state" --arg summary "$summary" \
      --arg decision "$decision" '{ts:$ts,pane:$pane,event:$event,previous:$previous,state:$state,summary:$summary,decision:$decision}' \
      >>"$(bonsai_state_dir)/events.jsonl"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$pane" "$event" "$previous" "$state" "$decision" \
      >>"$(bonsai_state_dir)/events.log"
  fi
}
