#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
base=$(wt_default_branch)
git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2); print $2}' | while read -r b; do
  [ "$b" = "$base" ] && continue
  if git merge-base --is-ancestor "$b" "$base" 2>/dev/null; then
    echo "pruning $b"
    wt remove --no-hooks "$b" && tmux kill-session -t "$(wt_sanitize "$b")" 2>/dev/null || true
  fi
done
echo; read -rn1 -p "[any key to close]"
