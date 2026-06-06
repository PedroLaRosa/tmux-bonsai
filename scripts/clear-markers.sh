#!/usr/bin/env bash
set -uo pipefail
# Panes are the source of truth; clear those (state + timestamp) plus the coarse
# window mirrors used by the optional status-line glyph.
tmux list-panes -a -F '#{pane_id}' | while read -r p; do
  tmux set-option -pu -t "$p" @agent_state 2>/dev/null || true
  tmux set-option -pu -t "$p" @agent_state_ts 2>/dev/null || true
done
tmux list-windows -a -F '#{window_id}' | while read -r w; do
  tmux set-option -wu -t "$w" @agent_state 2>/dev/null || true
done
