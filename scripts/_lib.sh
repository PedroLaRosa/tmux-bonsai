#!/usr/bin/env bash
# Shared helpers. The plugin does all tmux work itself, so it never relies on
# worktrunk hooks; every `wt` call below uses --no-hooks --no-cd.

wt_sanitize() { printf '%s' "$1" | sed 's#[/\\]#-#g'; }      # mirrors worktrunk's `sanitize`

# Run tmux against the server which invoked a hook.  TMUX contains
# "socket,pid,index"; using -S also makes delayed notification actions safe.
tmx() {
  local socket raw
  raw=${TMUX-}; socket=${BONSAI_SOCKET:-${raw%%,*}}
  if [ -n "$socket" ]; then
    command tmux -S "$socket" "$@"
  else
    command tmux "$@"
  fi
}

bonsai_dir() { CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd; }
bonsai_state_dir() {
  local d
  d=$(tmx show-option -gqv @bonsai-state-dir 2>/dev/null || true)
  printf '%s\n' "${d:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-bonsai}"
}

duration_seconds() {
  case ${1:-0} in
    *ms) awk -v n="${1%ms}" 'BEGIN { print n / 1000 }' ;;
    *[smhd])
      local n unit factor
      n=${1%?}; unit=${1#"$n"}; factor=1
      case $unit in m) factor=60;; h) factor=3600;; d) factor=86400;; esac
      awk -v n="$n" -v f="$factor" 'BEGIN { print n * f }'
      ;;
    *) printf '%s\n' "${1:-0}" ;;
  esac
}

tmux_at_least() {
  local want have
  want=$1; have=$(tmx -V | awk '{print $2}' | sed 's/[^0-9.].*//')
  awk -v h="$have" -v w="$want" 'BEGIN { exit !((h + 0) >= (w + 0)) }'
}

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
