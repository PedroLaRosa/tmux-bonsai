#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/_state.sh"

classify() {
  printf '%s' "$1" | jq -Rrs '
    if test("Cursor Agent|claude agents"; "i") then "none"
    elif test("[\u2800-\u28ff\u25d0-\u25d3✦⏲]") then "working"
    elif contains("✋") then "permission"
    elif test("[✳◇]") then "idle"
    elif test("(^|[^[:alnum:]_./~\\\\-])(ready|idle|done)($|[^[:alnum:]_./~\\\\-])"; "i") then "idle"
    elif test("(^|[^[:alnum:]_./~\\\\-])(working|thinking|running)($|[^[:alnum:]_./~\\\\-])"; "i") then "working"
    else "none" end'
}
if [ "${1:-}" = --classify ]; then classify "${2:-}"; exit 0; fi
if [ "${1:-}" = --settle ]; then
  pane=${2:-}; expected_seq=${3:-0}; delay=${4:-3}
  sleep "$delay"
  printf '{"expected_seq":%s}' "$expected_seq" | "$BONSAI_SCRIPTS/agent-event.sh" title title-settled --pane "$pane"
  exit 0
fi
pane=${1:-${TMUX_PANE:-}}
[ -n "$pane" ] || exit 0
[ "$(bonsai_opt @bonsai-titlewatch on)" != off ] || exit 0
title=$(tmx display-message -p -t "$pane" '#{pane_title}' 2>/dev/null) || exit 0
classification=$(classify "$title")
previous=$(bonsai_snapshot "$pane") || exit 0
[ -n "$previous" ] || exit 0
old_class=$(printf '%s' "$previous" | jq -r .title_state)
[ "$classification" != "$old_class" ] || exit 0
agent=$(printf '%s' "$previous" | jq -r .type)
if [ -z "$agent" ]; then
  pid=$(printf '%s' "$previous" | jq -r .pid)
  # Walk the pane shell's descendants once, only when title classification
  # changes. A random shell title containing "ready" is not an agent.
  agent=$(ps -eo pid=,ppid=,comm=,args= 2>/dev/null | awk -v root="$pid" '
    { parent[$1]=$2; text[$1]=$0 }
    END { for (pid in parent) { p=pid; for (n=0; n<100 && p && p!=root; n++) p=parent[p];
      if (p==root && match(text[pid], /(^|[ /])(claude|codex|opencode|gemini|cursor-agent|copilot|droid)([ /]|$)/)) {
        s=substr(text[pid],RSTART,RLENGTH); gsub(/^[ /]+|[ /]+$/, "", s); print s; exit
      }
    }}')
  # Still cache none; otherwise an unrelated title would repeatedly fork.
  if [ -z "$agent" ] && [ "$classification" != none ]; then exit 0; fi
fi
payload=$(jq -cn --arg classification "$classification" --arg agent "$agent" '{classification:$classification,agent:$agent}')
printf '%s' "$payload" | "$BONSAI_SCRIPTS/agent-event.sh" title title --pane "$pane"
if [ "$classification" = idle ]; then
  snapshot=$(bonsai_snapshot "$pane")
  if [ "$(printf '%s' "$snapshot" | jq -r .state)" = working ]; then
    delay=$(bonsai_duration "$(bonsai_opt @bonsai-title-settle 3s)")
    seq=$(printf '%s' "$snapshot" | jq -r .seq)
    bonsai_detach "$BONSAI_SCRIPTS/title.sh" --settle "$pane" "$seq" "$delay"
  fi
fi
