#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/_state.sh"

if [ "${1:-}" = --format ]; then
  ignored='#{m/ri:(Cursor Agent|claude agents),#{pane_title}}'
  permission='#{m/r:✋,#{pane_title}}'
  spinner='#{m/r:([⠀-⣿]|◐|◓|◑|◒|✦|⏲),#{pane_title}}'
  idle_glyph='#{m/r:(✳|◇),#{pane_title}}'
  working='#{m/ri:(^|[^a-zA-Z0-9_./~\\-])(working|thinking|running)($|[^a-zA-Z0-9_./~\\-]),#{pane_title}}'
  idle='#{m/ri:(^|[^a-zA-Z0-9_./~\\-])(ready|idle|done)($|[^a-zA-Z0-9_./~\\-]),#{pane_title}}'
  printf '#{?%s,none,#{?%s,permission,#{?%s,working,#{?%s,idle,#{?%s,idle,#{?%s,working,none}}}}}}\n' "$ignored" "$permission" "$spinner" "$idle_glyph" "$idle" "$working"
  exit 0
fi

classify() {
  printf '%s' "$1" | jq -Rrs '
    if test("Cursor Agent|claude agents"; "i") then "none"
    elif contains("✋") then "permission"
    elif test("[\u2800-\u28ff\u25d0-\u25d3✦⏲]") then "working"
    elif test("[✳◇]") then "idle"
    elif test("(^|[^a-zA-Z0-9_./~\\\\-])(ready|idle|done)($|[^a-zA-Z0-9_./~\\\\-])"; "i") then "idle"
    elif test("(^|[^a-zA-Z0-9_./~\\\\-])(working|thinking|running)($|[^a-zA-Z0-9_./~\\\\-])"; "i") then "working"
    else "none" end'
}
if [ "${1:-}" = --classify ]; then classify "${2:-}"; exit 0; fi
if [ "${1:-}" = --settle ]; then
  pane=${2:-}; expected_seq=${3:-0}; delay=${4:-3}
  sleep "$delay"
  snapshot=$(bonsai_snapshot "$pane") || exit 0
  printf '%s' "$snapshot" | jq -e '.state == "working" and .title_state == "idle"' >/dev/null || exit 0
  expected_seq=$(printf '%s' "$snapshot" | jq -r .seq)
  settle=$(bonsai_duration "$(bonsai_opt @bonsai-title-settle 3s)")
  if ! printf '%s' "$snapshot" | jq -e --argjson now "$(date +%s)" --argjson settle "$settle" \
    '$now - .hook_ts >= $settle and $now - .title_ts >= $settle' >/dev/null; then
    # Only fresh state evidence extends the quiet interval. Model/context and
    # message previews change seq too, but must not strand a stopped agent.
    bonsai_detach "$BONSAI_SCRIPTS/title.sh" --settle "$pane" "$expected_seq" "$settle"
    exit 0
  fi
  # Guard against an event arriving after this snapshot, once evidence is quiet.
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
      if (p==root && match(text[pid], /(^|[ \/])(claude|codex|opencode|gemini|cursor-agent|copilot|droid)([ \/]|$)/)) {
        s=substr(text[pid],RSTART,RLENGTH); gsub(/^[ \/]+|[ \/]+$/, "", s); print s; exit
      }
    }}')
  # Cache the classification even for unrelated processes: otherwise the tmux
  # gate would start a shell for every frame of an unrecognized spinner.
  if [ -z "$agent" ]; then
    tmx set-option -p -t "$pane" @agent_title_state "$classification" \; \
      set-option -p -t "$pane" @agent_title_ts "$(date +%s)" 2>/dev/null || true
    exit 0
  fi
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
