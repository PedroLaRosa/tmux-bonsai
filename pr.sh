#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
printf 'PR #: '; read -r n
[ -z "${n:-}" ] && exit 0
before=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | sort)
wt switch "pr:$n" --no-hooks --no-cd || { echo "wt switch pr failed"; sleep 1.5; exit 1; }
after=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | sort)
path=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n1)
branch=""
if [ -z "$path" ]; then                       # worktree already existed: resolve via gh
  branch=$(gh pr view "$n" --json headRefName -q .headRefName 2>/dev/null || true)
  [ -n "$branch" ] && path=$(wt_path_of "$branch")
fi
[ -z "$path" ] && { echo "could not locate PR worktree"; sleep 1.5; exit 1; }
branch=${branch:-$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null)}
wt_copy_ignored "$path"
S=$(wt_ensure_session "$branch" "$path")
tmux switch-client -t "$S"
