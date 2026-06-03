#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
flag="${1:--h}"                                          # -h = side-by-side (|), -v = stacked (_)
path=$(tmux display-message -p '#{pane_current_path}')
pane=$(tmux split-window "$flag" -c "$path" -P -F '#{pane_id}')
tmux send-keys -t "$pane" "$(wt_agent)" Enter
