#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
dir=$(tmx display-message -p '#{pane_current_path}')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || exit 0
win=$(tmx display-message -p '#{window_id}')
S=$(wt_ensure_session "$branch" "$dir")
tmx switch-client -t "$S"
tmx kill-window -t "$win" 2>/dev/null || true
