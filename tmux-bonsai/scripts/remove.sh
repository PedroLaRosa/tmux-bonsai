#!/usr/bin/env bash
# run-shell (server context) so it can't kill the shell doing the removal.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
dir=$(tmux display-message -p '#{pane_current_path}')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || exit 0
S=$(wt_sanitize "$branch")
sess=$(tmux display-message -p '#S')
win=$(tmux display-message -p '#W')
baseS=$(wt_sanitize "$(cd "$dir" && wt_default_branch)")
wt -C "$dir" remove --no-hooks "$branch" || exit 1
if [ "$sess" = "$S" ]; then                   # session-worktree
  tmux switch-client -t "$baseS" 2>/dev/null || true
  tmux kill-session -t "$S" 2>/dev/null || true
elif [ "$win" = "$S" ]; then                  # window-worktree
  tmux kill-window -t ":$S" 2>/dev/null || true
fi
