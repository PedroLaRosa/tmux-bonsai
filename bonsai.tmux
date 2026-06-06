#!/usr/bin/env bash
# tmux-bonsai — self-contained worktree management + agent notifications.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
key="$(tmux show-option -gqv @bonsai-key)"; key="${key:-W}"
tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/menu.sh"

# Optional opt-in direct key for the dashboard (default unset, so we never grab a key).
dkey="$(tmux show-option -gqv @bonsai-dashboard-key)"
[ -n "$dkey" ] && tmux bind-key "$dkey" run-shell -b "$CURRENT_DIR/scripts/launch.sh dashboard.sh"

# Clear an agent marker the moment you focus its pane. The pane option is the
# source of truth (cleared with its timestamp); the window option is the coarse
# single-agent mirror the optional status-line glyph reads.
if [ "$(tmux show-option -gqv @bonsai-notify)" = on ]; then
  tmux set-option -g focus-events on
  tmux set-hook -ga pane-focus-in 'set-option -pu @agent_state ; set-option -pu @agent_state_ts ; set-option -wu @agent_state'
fi
