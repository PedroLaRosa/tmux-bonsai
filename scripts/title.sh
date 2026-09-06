#!/usr/bin/env bash
set -u
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
pane=${1:-${TMUX_PANE:-}}; title=$(tmx display-message -p -t "$pane" '#{pane_title}')
case $title in *✋*|*[Pp]ermission*|*[Ww]aiting*) state=waiting;; *✳*|*◇*|*[Rr]eady*|*[Ii]dle*|*[Dd]one*) state=done;; *⠋*|*⠙*|*◐*|*◓*|*✦*|*[Ww]orking*|*[Tt]hinking*) state=working;; *) exit 0;; esac
current=$(tmx show-option -pqv -t "$pane" @agent_state 2>/dev/null || true); [ "$current" = "$state" ] && exit
exec "$S/agent-event.sh" mark "$pane" "$state" "$title"
