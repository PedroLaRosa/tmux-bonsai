#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
flag="${1:--h}"                                          # -h = side-by-side (|), -v = stacked (_)
path=$(tmx display-message -p '#{pane_current_path}')
pane=$(tmx split-window "$flag" -c "$path" -P -F '#{pane_id}')
wt_launch_agent "$pane"
