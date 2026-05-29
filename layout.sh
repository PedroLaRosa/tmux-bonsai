#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
sess=$(tmux display-message -p '#S')
dir=$(tmux display-message -p '#{pane_current_path}')
cw=$(tmux display-message -p '#W')
set -- $(wt_windows); first="$1"
case " $(wt_windows) " in *" $cw "*) ;; *) tmux rename-window -t "$sess" "$first" ;; esac
for w in $(wt_windows); do
  tmux list-windows -t "$sess" -F '#W' | grep -qx "$w" || tmux new-window -d -t "$sess" -n "$w" -c "$dir"
done
tmux select-window -t "$sess:$first"
