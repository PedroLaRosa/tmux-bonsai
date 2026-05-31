#!/usr/bin/env bash
# Shared helpers. The plugin does all tmux work itself, so it never relies on
# worktrunk hooks; every `wt` call below uses --no-hooks --no-cd.

wt_sanitize() { printf '%s' "$1" | sed 's#[/\\]#-#g'; }      # mirrors worktrunk's `sanitize`

# Signal launch.sh to re-open the bonsai menu, then exit cleanly. Used on cancel
# (fzf abort / empty prompt / key-to-close) so backing out returns to the menu.
wt_back() { tmux set-option -g @bonsai-back 1; exit 0; }

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

# Create a bare single-window session if it doesn't exist. Echoes the session name.
# Layout is the user's business (a separate plugin, or a tmux `session-created` hook).
wt_ensure_session() {                                       # branch path
  local S
  S=$(wt_sanitize "$1")
  tmux has-session -t "$S" 2>/dev/null || tmux new-session -d -s "$S" -c "$2"
  printf '%s' "$S"
}
