#!/usr/bin/env bash
# Popup wrapper: open the action in a display-popup, and if the action signalled
# "back" (cancel) via @bonsai-back, re-open the bonsai menu so it behaves like a
# navigable hierarchy instead of a one-shot launcher.
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
source "$S/_lib.sh"
path=$(tmx display-message -p '#{pane_current_path}')
tmx set-option -gu @bonsai-back 2>/dev/null          # clear stale flag

rel="$1"; shift                                       # e.g. new.sh [agent]
cmd=$(printf '%q ' "$S/$rel" "$@")
options=()
case "$rel" in board.sh|feed.sh|notify-*)
  options+=(-w 90% -h 85%)
  if bonsai_tmux_at_least 3.3; then options+=(-T ' bonsai · agents and notifications '); fi;;
esac
tmx display-popup "${options[@]}" -d "$path" -E "$cmd" # blocks until popup closes

if [ "$(tmx show-option -gqv @bonsai-back)" = 1 ]; then
  tmx set-option -gu @bonsai-back
  case "$rel" in notify-*) exec "$S/notify-menu.sh";; *) exec "$S/menu.sh";; esac
fi
