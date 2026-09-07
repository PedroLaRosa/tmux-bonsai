#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/_state.sh"
pane=${1:-${TMUX_PANE:-}}
if [ -z "$pane" ]; then pane=$(tmx display-message -p '#{pane_id}' 2>/dev/null); fi
[ -n "$pane" ] || exit 0
lock="bonsai-pane-${pane}"
tmx wait-for -L "$lock" 2>/dev/null || exit 0
trap 'tmx wait-for -U "$lock" >/dev/null 2>&1 || true' EXIT
state=$(bonsai_pane_opt "$pane" @agent_state) || exit 0
[ -n "$state" ] || exit 0
if [ "${2:-}" = --unread ]; then
  tmx set-option -p -t "$pane" @agent_seen_ts 0 2>/dev/null || true
else
  now=$(date +%s)
  tmx set-option -p -t "$pane" @agent_seen_ts "$now" \; \
    set-option -p -t "$pane" @agent_reminder_token '' 2>/dev/null || true
  if [ -x "$BONSAI_SCRIPTS/notify.sh" ]; then bonsai_detach "$BONSAI_SCRIPTS/notify.sh" dismiss "$pane"; fi
fi
tmx wait-for -U "$lock" 2>/dev/null || true
trap - EXIT
tmx refresh-client -S 2>/dev/null || true
if [ -x "$BONSAI_SCRIPTS/board.sh" ]; then bonsai_detach "$BONSAI_SCRIPTS/board.sh" --refresh; fi
