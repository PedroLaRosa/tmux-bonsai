#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
branch=$( {
    git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2);print $2}'
    git for-each-ref --format='%(refname:short)' refs/heads
    git for-each-ref --format='%(refname:short)' refs/remotes | grep -v '/HEAD$' | sed 's#^[^/]*/##'
  } | awk 'NF && !seen[$0]++' \
    | fzf --prompt='worktree/branch> ' \
          --preview 'git log --oneline --color=always -20 {} 2>/dev/null' ) || wt_back
[ -z "${branch:-}" ] && wt_back
path=$(wt_path_of "$branch")
if [ -z "$path" ]; then
  wt switch --no-hooks --no-cd "$branch" || { echo "wt switch failed"; sleep 1.5; exit 1; }
  path=$(wt_path_of "$branch"); wt_copy_ignored "$path"
fi
S=$(wt_ensure_session "$branch" "$path")
tmux switch-client -t "$S"
