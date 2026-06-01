#!/usr/bin/env bash
# Popup wrapper: open the action in a display-popup, and if the action signalled
# "back" (cancel) via @bonsai-back, re-open the bonsai menu so it behaves like a
# navigable hierarchy instead of a one-shot launcher.
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
path=$(tmux display-message -p '#{pane_current_path}')
tmux set-option -gu @bonsai-back 2>/dev/null          # clear stale flag

rel="$1"; shift                                       # e.g. new.sh [agent]
tmux display-popup -d "$path" -E "$(printf '%q ' "$S/$rel" "$@")"   # blocks until popup closes

if [ "$(tmux show-option -gqv @bonsai-back)" = 1 ]; then
  tmux set-option -gu @bonsai-back
  exec "$S/menu.sh"                                    # back to the menu
fi
