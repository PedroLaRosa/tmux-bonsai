#!/usr/bin/env bash
# Shared helpers. The plugin does all tmux work itself, so it never relies on
# worktrunk hooks; every `wt` call below uses --no-hooks --no-cd.

BONSAI_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BONSAI_SCRIPTS
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

bonsai_tmux_wire_init() {
  local socket=${1:-${BONSAI_SOCKET:-${TMUX:-}}} probe
  socket=${socket%%,*}
  if [ "${BONSAI_TMUX_DOLLAR_SOCKET-}" = "$socket" ] && [ -n "${BONSAI_TMUX_DOLLAR_ESCAPING:-}" ] && [ -n "${BONSAI_TMUX_DOLLAR_HIGH_BYTES:-}" ]; then return 0; fi
  if [ -n "$socket" ]; then
    probe=$(command tmux -S "$socket" display-message -p '$_bonsai_wire$é' 2>/dev/null) || return 0
  else
    probe=$(command tmux display-message -p '$_bonsai_wire$é' 2>/dev/null) || return 0
  fi
  BONSAI_TMUX_DOLLAR_SOCKET=$socket
  BONSAI_TMUX_DOLLAR_ESCAPING=off
  BONSAI_TMUX_DOLLAR_HIGH_BYTES=off
  case "$probe" in '\$_bonsai_wire'*) BONSAI_TMUX_DOLLAR_ESCAPING=on;; esac
  case "$probe" in *'\$é') BONSAI_TMUX_DOLLAR_HIGH_BYTES=on;; esac
  export BONSAI_TMUX_DOLLAR_SOCKET BONSAI_TMUX_DOLLAR_ESCAPING BONSAI_TMUX_DOLLAR_HIGH_BYTES
}
# Cache the server capability once and inherit it in detached workers. Legacy
# tmux adds a slash before $name/${name} even in supposedly raw command output.
bonsai_tmux_wire_init

tmx() {
  local socket="${BONSAI_SOCKET:-${TMUX:-}}" normalize=off dollar_class='a-zA-Z_{' decode_pattern
  socket=${socket%%,*}
  bonsai_tmux_wire_init "$socket"
  # These commands use tmux's formatted print path. Terminal captures are raw,
  # and interactive commands and mutations must retain their original streams.
  case "${1:-}" in
    display|display-message|show|show-option|show-options|show-environment|showenv|show-hooks|list-panes|list-clients|list-keys|list-windows|list-sessions)
      normalize=${BONSAI_TMUX_DOLLAR_ESCAPING:-off};;
  esac
  if [ "$normalize" = on ]; then
    # Remove exactly the server-added slash; preserve literal original slashes,
    # octal-looking text, command substitutions, and dollars before digits.
    # Legacy Darwin also calls byte isalpha on UTF-8 lead bytes. Its Latin-1
    # letters include C2-D6/D8-F4, but exclude D7 (multiplication sign), so
    # Unicode character classes would incorrectly decode e.g. a literal \$נ.
    [ "${BONSAI_TMUX_DOLLAR_HIGH_BYTES:-off}" != on ] || dollar_class="$dollar_class"$'\302-\326\330-\364'
    decode_pattern='s/\\(\$['"$dollar_class"'])/\1/g'
    if [ -n "$socket" ]; then
      command tmux -S "$socket" "$@" | LC_ALL=C sed -E "$decode_pattern"
      return "${PIPESTATUS[0]}"
    else
      command tmux "$@" | LC_ALL=C sed -E "$decode_pattern"
      return "${PIPESTATUS[0]}"
    fi
  fi
  if [ -n "$socket" ]; then command tmux -S "$socket" "$@"; else command tmux "$@"; fi
}
bonsai_server_key() {
  local socket="${BONSAI_SOCKET:-${TMUX:-default}}"
  local checksum
  checksum=$(printf '%s' "${socket%%,*}" | cksum)
  printf '%s' "${checksum%% *}"
}
bonsai_opt() {
  local value
  value=$(tmx show-option -gqv "$1" 2>/dev/null) || value=''
  printf '%s' "${value:-${2:-}}"
}
bonsai_state_dir() {
  bonsai_opt @bonsai-state-dir "${XDG_STATE_HOME:-$HOME/.local/state}/tmux-bonsai"
}
bonsai_config_dir() {
  bonsai_opt @bonsai-config-dir "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-bonsai"
}
bonsai_duration() {
  awk -v v="$1" 'BEGIN {
    if (v !~ /^[0-9]+([.][0-9]+)?[smh]?$/) exit 1;
    m=1; if (v ~ /m$/) m=60; if (v ~ /h$/) m=3600;
    sub(/[smh]$/, "", v); printf "%g\n", v*m
  }'
}
bonsai_tmux_at_least() {
  local version
  version=$(tmx -V 2>/dev/null)
  awk -v actual="${version#tmux }" -v required="$1" 'BEGIN {
    split(actual,a,"."); split(required,r,".");
    exit !(a[1]+0>r[1]+0 || (a[1]+0==r[1]+0 && a[2]+0>=r[2]+0))
  }'
}
tmux_at_least() { bonsai_tmux_at_least "$@"; }
bonsai_shell_quote() {
  # Quote replacement via variables: Bash 3.2 parses backslashes in an inline
  # parameter-substitution replacement differently from current Bash.
  local value=$1 quote="'" replacement="'\\''"
  value=${value//"$quote"/"$replacement"}
  printf "'%s'" "$value"
}
bonsai_tmux_quote() {
  local value=$1
  value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//\$/\\\$}; value=${value//\`/\\\`}
  printf '"%s"' "$value"
}
bonsai_run_command() {
  local background='' cmd='' arg
  if [ "${1:-}" = -b ]; then background='-b '; shift; fi
  for arg in "$@"; do cmd="$cmd$(bonsai_shell_quote "$arg") "; done
  printf 'run-shell %s%s' "$background" "$(bonsai_tmux_quote "$cmd")"
}
bonsai_detach() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" </dev/null >/dev/null 2>&1 &
  else
    nohup "$@" </dev/null >/dev/null 2>&1 &
  fi
}
bonsai_glyph() {
  local glyphs="${BONSAI_GLYPHS:-}"
  [ -n "$glyphs" ] || glyphs=$(bonsai_opt @bonsai-glyphs unicode)
  case "$glyphs:$1" in
    ascii:waiting) printf '[!]' ;; ascii:working) printf '[~]' ;; ascii:done) printf '[+]' ;;
    ascii:idle) printf '[.]' ;; ascii:error) printf '[x]' ;; ascii:stopped) printf '[-]' ;;
    ascii:exited) printf '[z]' ;; ascii:*) printf '[?]' ;;
    emoji:waiting) printf '💬' ;; emoji:working) printf '🔄' ;; emoji:done) printf '✅' ;;
    emoji:idle) printf '✓' ;; emoji:error) printf '❗' ;; emoji:stopped) printf '⛔' ;;
    emoji:exited) printf '💤' ;; emoji:*) printf '❔' ;;
    *:waiting) printf '●' ;; *:working) printf '◐' ;; *:done) printf '✔' ;; *:idle) printf '·' ;;
    *:error) printf '✖' ;; *:stopped) printf '■' ;; *:exited) printf '○' ;; *) printf '?' ;;
  esac
}

wt_sanitize() { printf '%s' "$1" | sed 's#[/\\]#-#g'; }      # mirrors worktrunk's `sanitize`

# Signal launch.sh to re-open the bonsai menu, then exit cleanly. Used on cancel
# (fzf abort / empty prompt / key-to-close) so backing out returns to the menu.
wt_back() { tmx set-option -g @bonsai-back 1; exit 0; }

wt_agent() {
  local a; a=$(tmx show-option -gqv @bonsai-agent)
  printf '%s' "${a:-claude}"
}

wt_launch_agent() {
  local pane command now agent
  pane=$(tmx display-message -p -t "$1" '#{pane_id}') || return 1
  command=$(wt_agent); agent=${command%% *}; agent=${agent##*/}; now=$(date +%s)
  tmx set -p -t "$pane" @agent_launch_ts "$now" \; set -p -t "$pane" @agent_state unknown \; \
    set -p -t "$pane" @agent_state_ts "$now" \; set -p -t "$pane" @agent_type "$agent"
  tmx send-keys -t "$pane" -l -- "$command" && tmx send-keys -t "$pane" Enter
}

wt_path_of() {                                              # branch -> worktree path ('' if none)
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree /{w=substr($0,10)} /^branch /{if($2==b) print w}'
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
  tmx has-session -t "$S" 2>/dev/null || tmx new-session -d -s "$S" -c "$2"
  printf '%s' "$S"
}
