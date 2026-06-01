#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
mode="${1:-}"
printf 'new worktree%s: ' "${mode:+ + $mode}"; read -r branch
[ -z "${branch:-}" ] && wt_back
wt switch --create --no-hooks --no-cd "$branch" || { echo "wt switch failed"; sleep 1.5; exit 1; }
path=$(wt_path_of "$branch"); wt_copy_ignored "$path"
S=$(wt_ensure_session "$branch" "$path")
tmux switch-client -t "$S"
if [ "$mode" = agent ]; then
  tmux send-keys -t "$S" "$(wt_agent)" Enter
fi
