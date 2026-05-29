#!/usr/bin/env bash
# Raise an alert for the agent running in the CURRENT tmux pane.
# Usage: notify.sh <waiting|done|error> [message]
# Called from a Claude Code hook or an opencode plugin, which run inside the
# agent's pane, so $TMUX_PANE points at the right pane.
set -uo pipefail
[ -z "${TMUX:-}" ] && exit 0
state="${1:-done}"; msg="${2:-}"
pane="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}"

info=$(tmux display-message -p -t "$pane" \
  '#{window_id}|#{session_name}|#{window_name}|#{window_active}|#{session_attached}')
IFS='|' read -r win sess wname active attached <<<"$info"

# mark the window so the status line / `clear-markers` can reflect it
tmux set-option -w -t "$win" @agent_state "$state"

# if you're already looking at this window, mark only — don't be loud
if [ "${active:-0}" = "1" ] && [ "${attached:-0}" != "0" ]; then
  exit 0
fi

case "$state" in
  waiting) icon="💬"; title="Agent waiting for input" ;;
  error)   icon="❗"; title="Agent error" ;;
  *)       icon="✅"; title="Agent finished" ;;
esac
body="[$sess] ${msg:-$wname}"

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a bonsai "$icon $title" "$body"
elif command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$icon $title" -message "$body" -group "wt-$sess" >/dev/null 2>&1
elif command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$body\" with title \"$icon $title\"" >/dev/null 2>&1
fi
