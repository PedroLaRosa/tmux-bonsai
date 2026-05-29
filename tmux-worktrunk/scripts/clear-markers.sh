#!/usr/bin/env bash
set -uo pipefail
tmux list-windows -a -F '#{window_id}' | while read -r w; do
  tmux set-option -u -w -t "$w" @agent_state 2>/dev/null || true
done
