#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
dir=$(tmux display-message -p '#{pane_current_path}')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || exit 0
win=$(tmux display-message -p '#{window_id}')
S=$(wt_ensure_session "$branch" "$dir")
tmux switch-client -t "$S"
tmux kill-window -t "$win" 2>/dev/null || true
