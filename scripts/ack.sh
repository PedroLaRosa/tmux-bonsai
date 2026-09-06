#!/usr/bin/env bash
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
pane=${1:-$(tmx display-message -p '#{pane_id}')}
tmx set-option -pq -t "$pane" @agent_unread 0 2>/dev/null || true
