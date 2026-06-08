#!/usr/bin/env bash
# run-shell (server context) so it can't kill the shell doing the removal.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
dir=$(tmux display-message -p '#{pane_current_path}')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || exit 0
S=$(wt_sanitize "$branch")
sess=$(tmux display-message -p '#S')
win=$(tmux display-message -p '#W')
# Resolve the default-branch "home" target and the main worktree before removal
# (the main worktree survives, but $dir does not, so read everything from $dir first).
defbr=$(cd "$dir" && wt_default_branch)
baseS=$(wt_sanitize "$defbr")
basePath=$(cd "$dir" && wt_path_of "$defbr")
main=$(cd "$dir" && wt_main_worktree)
# Remove the worktree, then delete its branch only if it's merged: `git branch -d`
# refuses unmerged branches, mirroring worktrunk's "delete branch if merged".
git -C "$main" worktree remove "$dir" || exit 1
git -C "$main" branch -d "$branch" 2>/dev/null || true
if [ "$sess" = "$S" ]; then                   # session-worktree
  if [ "$baseS" != "$S" ]; then               # don't try to "go home" to ourselves
    [ -n "$basePath" ] && wt_ensure_session "$defbr" "$basePath" >/dev/null
    tmux switch-client -t "$baseS" 2>/dev/null || true
  fi
  tmux kill-session -t "$S" 2>/dev/null || true
elif [ "$win" = "$S" ]; then                  # window-worktree
  tmux kill-window -t ":$S" 2>/dev/null || true
fi
