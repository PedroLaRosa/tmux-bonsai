#!/usr/bin/env bash
# tmux-worktrunk — self-contained worktree management + agent notifications.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
key="$(tmux show-option -gqv @worktrunk-key)"; key="${key:-W}"
tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/menu.sh"

# Clear a window's agent marker as soon as you focus it.
if [ "$(tmux show-option -gqv @worktrunk-notify)" = on ]; then
  tmux set-option -g focus-events on
  tmux set-hook -ga pane-focus-in 'set-option -u -w @agent_state'
fi
