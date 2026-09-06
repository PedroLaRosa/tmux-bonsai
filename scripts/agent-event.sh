#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_state.sh"
agent=${1:-generic}; event=${2:-}; payload=${3:-}
if [ "$agent" = mark ]; then
  pane=$event; state=${payload:-waiting}; summary=${4:-}; event=mark; agent=manual
else
  pane=${TMUX_PANE:-}; summary=
  [ -t 0 ] || payload=$(cat)
  if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
    summary=$(printf '%s' "$payload" | jq -r '.last_assistant_message // .message // .notification // .tool_name // empty' 2>/dev/null || true)
  fi
  case $event in
    UserPromptSubmit|PreToolUse|PostToolUse|PostToolUseFailure|session.created|session.status) state=working ;;
    PermissionRequest|Notification|permission.asked|agent_needs_input) state=waiting ;;
    Stop|StopFailure|session.idle|agent_completed) state=done ;;
    session.error|error) state=error ;;
    SessionStart|PostCompact) state=idle ;;
    *) state=${payload:-working} ;;
  esac
fi
[ -n "$pane" ] || { echo 'bonsai: pane is required' >&2; exit 2; }
previous=$(tmx show-option -pqv -t "$pane" @agent_state 2>/dev/null || true)
now=$(date +%s)
state_set "$pane" state "$state" state_ts "$now" type "$agent" msg "$summary" unread "$([ "$state" = done ] || [ "$state" = waiting ] || [ "$state" = error ] && echo 1 || echo 0)"
state_log "$pane" "$event" "$previous" "$state" "$summary" tracked
tmx refresh-client -S 2>/dev/null || true
case $state in waiting|done|error) "$S/notify.sh" event "$pane" "$state" "$summary" >/dev/null 2>&1 & ;; esac
