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
S=$(wt_ensure_session "$branch" "$path")
tmux switch-client -t "$S"
