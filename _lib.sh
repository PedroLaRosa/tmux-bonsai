#!/usr/bin/env bash
# Shared helpers. The plugin does all tmux work itself, so it never relies on
# worktrunk hooks; every `wt` call below uses --no-hooks --no-cd.

wt_sanitize() { printf '%s' "$1" | sed 's#[/\\]#-#g'; }      # mirrors worktrunk's `sanitize`

wt_windows() {                                              # layout window names
  local w; w=$(tmux show-option -gqv @bonsai-windows)
  printf '%s' "${w:-edit agent serve git}"
}

wt_agent() {
  local a; a=$(tmux show-option -gqv @bonsai-agent)
  printf '%s' "${a:-claude}"
}

wt_path_of() {                                              # branch -> worktree path ('' if none)
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree /{w=$2} /^branch /{if($2==b) print w}'
}

wt_default_branch() {
  wt config state default-branch 2>/dev/null \
    || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' \
    || echo main
}

wt_copy_ignored() {                                         # path -> copy .env etc into it
  [ -n "${1:-}" ] && ( cd "$1" && wt step copy-ignored ) >/dev/null 2>&1 || true
}

# Create the session + window layout if it doesn't exist. Echoes the session name.
wt_ensure_session() {                                       # branch path
  local S p first w
  S=$(wt_sanitize "$1"); p="$2"
  if ! tmux has-session -t "$S" 2>/dev/null; then
    set -- $(wt_windows); first="$1"; shift
    tmux new-session -d -s "$S" -c "$p" -n "$first"
    for w in "$@"; do tmux new-window -d -t "$S" -n "$w" -c "$p"; done
  fi
  printf '%s' "$S"
}
