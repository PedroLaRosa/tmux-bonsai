#!/usr/bin/env bash
# Shared helpers. The plugin drives native `git worktree` directly — no external
# worktree tool — and does all tmux work itself, so it stays dependency-free
# beyond git + tmux (+ fzf for the picker).

wt_sanitize() { printf '%s' "$1" | sed 's#[/\\]#-#g'; }    # filesystem-safe branch name

# Signal launch.sh to re-open the bonsai menu, then exit cleanly. Used on cancel
# (fzf abort / empty prompt / key-to-close) so backing out returns to the menu.
wt_back() { tmux set-option -g @bonsai-back 1; exit 0; }

wt_agent() {
  local a; a=$(tmux show-option -gqv @bonsai-agent)
  printf '%s' "${a:-claude}"
}

wt_path_of() {                                             # branch -> worktree path ('' if none)
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree /{w=$2} /^branch /{if($2==b) print w}'
}

# Absolute path of the repo's main worktree (git always lists it first), even when
# called from inside a linked worktree.
wt_main_worktree() {
  git worktree list --porcelain | awk '/^worktree /{print $2; exit}'
}

# Worktree path for a branch: a sibling of the main worktree named
# "<repo>.<sanitized-branch>" (e.g. ~/code/app -> ~/code/app.feature-x).
wt_worktree_path() {                                       # branch -> path
  printf '%s.%s' "$(wt_main_worktree)" "$(wt_sanitize "$1")"
}

# The repo's default branch: origin/HEAD if known, else main/master, else main.
wt_default_branch() {
  local d
  d=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) \
    && { printf '%s' "${d#origin/}"; return; }
  for d in main master; do
    git show-ref --verify --quiet "refs/heads/$d" && { printf '%s' "$d"; return; }
  done
  printf 'main'
}

# First remote-tracking ref whose branch part matches $1 ('' + non-zero if none).
# Mirrors the picker, which strips the remote prefix (origin/feat -> feat).
wt_remote_ref() {                                          # branch -> "<remote>/<branch>" or ''
  local b=${1:-} ref
  while IFS= read -r ref; do
    case "$ref" in */HEAD) continue;; esac
    [ "${ref#*/}" = "$b" ] && { printf '%s' "$ref"; return 0; }
  done < <(git for-each-ref --format='%(refname:short)' refs/remotes)
  return 1
}

# Create a brand-new branch + worktree, based off the default branch (matching the
# old `wt switch --create` semantics). Prints the path; non-zero on failure.
wt_create() {                                              # branch -> path
  local branch=$1 path base
  path=$(wt_worktree_path "$branch")
  base=$(wt_default_branch)
  git show-ref --verify --quiet "refs/heads/$base" || base="origin/$base"
  git worktree add -b "$branch" "$path" "$base" >/dev/null 2>&1 || return 1
  printf '%s' "$path"
}

# Check an existing local/remote branch out into a fresh worktree (a remote-only
# branch gets a local tracking branch). Prints the path; non-zero on failure.
wt_checkout() {                                            # branch -> path
  local branch=$1 path ref
  path=$(wt_worktree_path "$branch")
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$path" "$branch" >/dev/null 2>&1 || return 1
  elif ref=$(wt_remote_ref "$branch"); then
    git worktree add -b "$branch" "$path" "$ref" >/dev/null 2>&1 || return 1
  else
    return 1
  fi
  printf '%s' "$path"
}

# Copy gitignored entries (.env, build caches, deps, ...) from the main worktree
# into a new one so it works out of the box. Best-effort; never fails the caller.
wt_copy_ignored() {                                        # dest-path
  local dest=${1:-} src f
  [ -n "$dest" ] || return 0
  src=$(wt_main_worktree)
  [ -n "$src" ] && [ "$src" != "$dest" ] || return 0
  ( cd "$src" 2>/dev/null || exit 0
    while IFS= read -r -d '' f; do
      f=${f%/}
      case "$f" in .git|.git/*|.worktrees|.worktrees/*) continue;; esac
      mkdir -p "$dest/$(dirname "$f")" 2>/dev/null || continue
      cp -R "$f" "$dest/$f" 2>/dev/null || true
    done < <(git ls-files -z --others --ignored --exclude-standard --directory)
  ) >/dev/null 2>&1 || true
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

# Create a bare single-window session if it doesn't exist. Echoes the session name.
# Layout is the user's business (a separate plugin, or a tmux `session-created` hook).
wt_ensure_session() {                                      # branch path
  local S
  S=$(wt_sanitize "$1")
  tmux has-session -t "$S" 2>/dev/null || tmux new-session -d -s "$S" -c "$2"
  printf '%s' "$S"
}
