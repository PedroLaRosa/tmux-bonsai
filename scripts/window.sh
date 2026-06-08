#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
mode="${1:-}"
printf 'worktree as window%s: ' "${mode:+ + $mode}"; read -r branch
[ -z "${branch:-}" ] && wt_back
path=$(wt_create "$branch") || { echo "worktree create failed"; sleep 1.5; exit 1; }
wt_copy_ignored "$path"
S=$(wt_sanitize "$branch")
tmux new-window -c "$path" -n "$S"
tmux select-window -t ":$S"
if [ "$mode" = agent ]; then
  tmux send-keys -t ":$S" "$(wt_agent)" Enter
fi
