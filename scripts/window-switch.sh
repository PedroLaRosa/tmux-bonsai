#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
branch=$(wt_pick_branch) || wt_back
[ -z "${branch:-}" ] && wt_back
path=$(wt_path_of "$branch")
if [ -z "$path" ]; then
  path=$(wt_checkout "$branch") || { echo "worktree switch failed"; sleep 1.5; exit 1; }
  wt_copy_ignored "$path"
fi
S=$(wt_sanitize "$branch")
# Jump to the worktree's window if it already exists, else open one for it.
tmux select-window -t ":$S" 2>/dev/null || {
  tmux new-window -c "$path" -n "$S"
  tmux select-window -t ":$S"
}
