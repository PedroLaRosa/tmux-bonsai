#!/usr/bin/env bash
# Raise an alert for the agent running in the CURRENT tmux pane.
# Usage: notify.sh <working|waiting|done|error> [message]
# Called from a Claude Code hook or an opencode plugin, which run inside the
# agent's pane, so $TMUX_PANE points at the right pane.
set -uo pipefail
[ -z "${TMUX:-}" ] && exit 0
state="${1:-done}"; msg="${2:-}"
pane="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}"

info=$(tmux display-message -p -t "$pane" \
  '#{window_id}|#{session_name}|#{window_name}|#{pane_active}|#{window_active}|#{session_attached}')
IFS='|' read -r win sess wname pactive wactive attached <<<"$info"

# The pane is the source of truth — one row per agent in the dashboard — and we
# stamp when the state last changed so the dashboard can show its age. The window
# option is a coarse single-agent rollup kept only for the optional status-line glyph.
tmux set-option -p -t "$pane" @agent_state "$state"
tmux set-option -p -t "$pane" @agent_state_ts "$(date +%s)"
tmux set-option -w -t "$win" @agent_state "$state"

# `working` is mark-only: it fires on every turn, so alerting would be spam.
[ "$state" = working ] && exit 0

# if you're already looking at this exact pane, mark only — don't be loud
if [ "${pactive:-0}" = "1" ] && [ "${wactive:-0}" = "1" ] && [ "${attached:-0}" != "0" ]; then
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
