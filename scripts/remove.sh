#!/usr/bin/env bash
# run-shell (server context) so it can't kill the shell doing the removal.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
dir=$(tmx display-message -p '#{pane_current_path}')
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || exit 0
S=$(wt_sanitize "$branch")
sess=$(tmx display-message -p '#S')
win=$(tmx display-message -p '#W')
# Resolve the default-branch "home" target before removal (its worktree path
# survives `wt remove`, but $dir does not, so read everything from $dir first).
defbr=$(cd "$dir" && wt_default_branch)
baseS=$(wt_sanitize "$defbr")
basePath=$(cd "$dir" && wt_path_of "$defbr")
wt -C "$dir" remove --no-hooks "$branch" || exit 1
if [ "$sess" = "$S" ]; then                   # session-worktree
  if [ "$baseS" != "$S" ]; then               # don't try to "go home" to ourselves
    [ -n "$basePath" ] && wt_ensure_session "$defbr" "$basePath" >/dev/null
    tmx switch-client -t "$baseS" 2>/dev/null || true
  fi
  tmx kill-session -t "$S" 2>/dev/null || true
elif [ "$win" = "$S" ]; then                  # window-worktree
  tmx kill-window -t ":$S" 2>/dev/null || true
fi
