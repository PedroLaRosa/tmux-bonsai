#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
pane=${1:?usage: bonsai jump PANE}
target=$(tmx display-message -p -t "$pane" '#{session_name}:#{window_index}.#{pane_index}')
tmx switch-client -t "${target%%:*}" 2>/dev/null || true
tmx select-window -t "${target%.*}"; tmx select-pane -t "$target"
tmx set-option -pq -t "$pane" @agent_unread 0
tmx display-message "bonsai: focused $target"
