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

# fzf-pick a worktree/branch and print it. Returns fzf's exit code so callers can
# `branch=$(wt_pick_branch) || wt_back` — it must NOT call wt_back itself, since
# that runs in the $(...) subshell and would fail to exit the parent script.
wt_pick_branch() {
  {
    git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2);print $2}'
    git for-each-ref --format='%(refname:short)' refs/heads
    git for-each-ref --format='%(refname:short)' refs/remotes | grep -v '/HEAD$' | sed 's#^[^/]*/##'
  } | awk 'NF && !seen[$0]++' \
    | fzf --prompt='worktree/branch> ' \
          --preview 'git log --oneline --color=always -20 {} 2>/dev/null'
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
