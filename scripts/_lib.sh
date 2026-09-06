#!/usr/bin/env bash
# Shared helpers for tmux-bonsai.
#
# Portability contract (see docs/plan-notifications-dashboard.md §9):
#   * bash 3.2 (macOS stock): no associative arrays, no `mapfile`, no ${var,,}.
#   * BSD *and* GNU userland: no `sed -i`, `readlink -f`, `stat -c`, `date -d`,
#     `timeout`, `flock`.
#   * Every tmux call goes through tmx() so a hook running outside the server's
#     environment still talks to the right socket.
#
# The worktree helpers (wt_*) predate the agent work and are unchanged; the
# plugin still does all tmux work itself and never relies on worktrunk hooks.

# ---------------------------------------------------------------- environment

# `run-shell` hooks inherit the tmux *server's* environment, which is often the
# login shell's PATH from before Homebrew was on it. terminal-notifier living in
# /opt/homebrew/bin and being invisible to the server is the classic "my
# notifications stopped working" report, so put the usual suspects back.
bs_fix_path() {
  local d
  for d in "$HOME/.local/bin" /usr/local/bin /opt/homebrew/bin; do
    case ":$PATH:" in
      *":$d:"*) ;;
      *) [ -d "$d" ] && PATH="$PATH:$d" ;;
    esac
  done
  export PATH
}
bs_fix_path

# tmux renders format output through the *client's* locale: with a non-UTF-8
# LC_CTYPE every non-ASCII byte comes back as `_`, which would shred agent
# messages, branch names and our own glyphs. tmux hooks run with the server's
# environment, which under systemd/launchd is often bare, so fix LC_CTYPE up
# ourselves. bash's ${str:0:n} slicing needs the same thing to cut on character
# rather than byte boundaries.
bs_fix_locale() {
  case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in
    *[Uu][Tt][Ff]8*|*[Uu][Tt][Ff]-8*) return 0 ;;
  esac
  local c
  for c in C.UTF-8 C.utf8 en_US.UTF-8 UTF-8; do
    if locale -a 2>/dev/null | grep -qxF "$c"; then
      LC_CTYPE="$c"; export LC_CTYPE; unset LC_ALL 2>/dev/null || true; return 0
    fi
  done
  return 0
}
bs_fix_locale

# Plugin root: scripts/ lives directly under it.
BONSAI_SCRIPTS="${BONSAI_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)}"
BONSAI_ROOT="${BONSAI_ROOT:-$(cd "$BONSAI_SCRIPTS/.." && pwd -P)}"
export BONSAI_SCRIPTS BONSAI_ROOT

# Socket. Notification click handlers and detached sleepers run with no $TMUX,
# so `bonsai -S <socket>` passes it explicitly; hooks derive it from $TMUX,
# whose first comma-separated field is the socket path.
if [ -z "${BONSAI_SOCKET:-}" ] && [ -n "${TMUX:-}" ]; then
  BONSAI_SOCKET="${TMUX%%,*}"
fi
export BONSAI_SOCKET

# tmx: the only way this plugin talks to tmux.
tmx() {
  if [ -n "${BONSAI_SOCKET:-}" ]; then
    command tmux -S "$BONSAI_SOCKET" "$@"
  else
    command tmux "$@"
  fi
}

bs_have() { command -v "$1" >/dev/null 2>&1; }

bs_now() { date +%s; }

# ------------------------------------------------------------------- options

# Global user option with a fallback. tmux returns empty both for "unset" and
# for "set to the empty string"; for @bonsai-* options that distinction never
# matters (an empty value always means "use the default").
bs_opt() {                                        # NAME DEFAULT
  local v
  v=$(tmx show-option -gqv "$1" 2>/dev/null)
  if [ -z "$v" ]; then printf '%s' "${2:-}"; else printf '%s' "$v"; fi
}

# Pane option with a fallback.
bs_popt() {                                       # PANE NAME DEFAULT
  local v
  v=$(tmx display-message -p -t "$1" "#{$2}" 2>/dev/null)
  if [ -z "$v" ]; then printf '%s' "${3:-}"; else printf '%s' "$v"; fi
}

bs_is_on() { case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in on|1|yes|true) return 0;; *) return 1;; esac; }

# Both directories are read on nearly every code path, and each read is a fork
# into the tmux server, so memoise them per process.
bs_state_dir() {
  if [ -z "${_BS_STATE_DIR:-}" ]; then
    _BS_STATE_DIR=$(bs_opt @bonsai-state-dir "")
    [ -n "$_BS_STATE_DIR" ] || _BS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-bonsai"
  fi
  printf '%s' "$_BS_STATE_DIR"
}

bs_config_dir() {
  if [ -z "${_BS_CONFIG_DIR:-}" ]; then
    _BS_CONFIG_DIR=$(bs_opt @bonsai-config-dir "")
    [ -n "$_BS_CONFIG_DIR" ] || _BS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-bonsai"
  fi
  printf '%s' "$_BS_CONFIG_DIR"
}

# ------------------------------------------------------------------ versions

# bs_version_ge 3.4 3.3  -> true. Compares dotted numbers; a trailing letter in
# a tmux version ("3.3a") sorts after the plain number, which is what we want.
bs_version_ge() {                                 # HAVE WANT
  local have="${1:-0}" want="${2:-0}" h w i
  have=$(printf '%s' "$have" | sed 's/[^0-9.].*$//')
  want=$(printf '%s' "$want" | sed 's/[^0-9.].*$//')
  i=1
  while [ "$i" -le 3 ]; do
    h=$(printf '%s' "$have" | cut -d. -f"$i"); w=$(printf '%s' "$want" | cut -d. -f"$i")
    [ -n "$h" ] || h=0; [ -n "$w" ] || w=0
    case "$h" in ''|*[!0-9]*) h=0;; esac
    case "$w" in ''|*[!0-9]*) w=0;; esac
    [ "$h" -gt "$w" ] && return 0
    [ "$h" -lt "$w" ] && return 1
    i=$((i + 1))
  done
  return 0
}

bs_tmux_version() {
  command tmux -V 2>/dev/null | awk '{print $2}'
}

bs_tmux_at_least() {                              # VERSION
  bs_version_ge "$(bs_tmux_version)" "$1"
}

bs_fzf_version() { fzf --version 2>/dev/null | awk '{print $1}'; }
bs_fzf_at_least() { bs_have fzf || return 1; bs_version_ge "$(bs_fzf_version)" "$1"; }

# ----------------------------------------------------------------- durations

# Accepts `5`, `1.5`, `30s`, `10m`, `2h`, `off`/`none`/`0` (prints nothing for
# "off" so callers can test with -z). Fractions survive for `sleep`.
bs_dur() {                                        # SPEC
  local s="${1:-}" n u
  case "$(printf '%s' "$s" | tr 'A-Z' 'a-z')" in
    ''|off|none|no|false) return 0 ;;
  esac
  n=$(printf '%s' "$s" | sed 's/[^0-9.].*$//')
  u=$(printf '%s' "$s" | sed 's/^[0-9.]*//' | tr 'A-Z' 'a-z')
  [ -n "$n" ] || return 0
  case "$u" in
    h|hr|hour|hours)   awk -v n="$n" 'BEGIN{printf "%s", n*3600}' ;;
    m|min|mins|minute|minutes) awk -v n="$n" 'BEGIN{printf "%s", n*60}' ;;
    d|day|days)        awk -v n="$n" 'BEGIN{printf "%s", n*86400}' ;;
    *)                 printf '%s' "$n" ;;
  esac
}

# Integer seconds, rounded up — for comparisons against epoch arithmetic.
bs_dur_i() {                                      # SPEC
  local d; d=$(bs_dur "${1:-}")
  [ -n "$d" ] || return 0
  awk -v d="$d" 'BEGIN{printf "%d", (d == int(d)) ? d : int(d)+1}'
}

# 41s / 12m / 3h / 2d — the board's age column.
bs_age_fmt() {                                    # SECONDS
  local s="${1:-0}"
  case "$s" in ''|*[!0-9]*) printf '%s' '—'; return 0 ;; esac
  if   [ "$s" -lt 60 ];    then printf '%ss' "$s"
  elif [ "$s" -lt 3600 ];  then printf '%sm' "$((s / 60))"
  elif [ "$s" -lt 86400 ]; then printf '%sh' "$((s / 3600))"
  else                          printf '%sd' "$((s / 86400))"
  fi
}

# ------------------------------------------------------------ text hygiene

# Strip control characters (keeping nothing that could break a tmux format, a
# 0x1F-delimited board row, or a JSON line) and squeeze runs of whitespace.
bs_sanitize() {                                   # TEXT
  printf '%s' "${1:-}" \
    | tr '\n\r\t\037\013\014' '      ' \
    | tr -d '\001-\010\016-\032\034-\036\177' \
    | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# Truncate to N characters with an ellipsis. bash slices by character in a
# UTF-8 locale, so this does not split a multibyte sequence.
bs_trunc() {                                      # TEXT N
  local t="${1:-}" n="${2:-160}"
  if [ "${#t}" -gt "$n" ]; then printf '%s…' "${t:0:$((n - 1))}"; else printf '%s' "$t"; fi
}

bs_clean() { bs_trunc "$(bs_sanitize "${1:-}")" "${2:-160}"; }

# A value that is *exactly* `;` is indistinguishable from tmux's argv command
# separator, and a chained `set-option a ; set-option b` carrying one fails
# wholesale ("empty value") rather than just mangling that field. Verified on
# 3.4. Nudge it so the chain survives; nothing else needs escaping, because a
# value with any other character is never a separator.
bs_argv_safe() {                                  # VALUE
  case "${1:-}" in
    ';') printf '; ' ;;
    *)   printf '%s' "${1:-}" ;;
  esac
}

# JSON string literal, quotes included.
bs_json() {                                       # TEXT
  if bs_have jq; then
    printf '%s' "${1:-}" | jq -Rs .
  else
    printf '"%s"' "$(printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr -d '\n')"
  fi
}

# ------------------------------------------------------------------- glyphs

# One table, every surface (board, feed, status line, banners, window glyph).
# Default is single-width unicode: emoji misalign status lines on many
# terminals, so it stays opt-in.
bs_glyph() {                                      # STATE [SET]
  local st="${1:-unknown}" set="${2:-}"
  [ -n "$set" ] || set=$(bs_opt @bonsai-glyphs unicode)
  case "$set" in
    emoji)
      case "$st" in
        waiting) printf '💬' ;; working) printf '🔄' ;; done) printf '✅' ;;
        idle)    printf '✓'  ;; error)   printf '❗' ;; stopped) printf '⛔' ;;
        exited)  printf '💤' ;; *)       printf '❔' ;;
      esac ;;
    ascii)
      case "$st" in
        waiting) printf '[!]' ;; working) printf '[~]' ;; done) printf '[+]' ;;
        idle)    printf '[.]' ;; error)   printf '[x]' ;; stopped) printf '[-]' ;;
        exited)  printf '[z]' ;; *)       printf '[?]' ;;
      esac ;;
    *)
      case "$st" in
        waiting) printf '●' ;; working) printf '◐' ;; done) printf '✔' ;;
        idle)    printf '·' ;; error)   printf '✖' ;; stopped) printf '■' ;;
        exited)  printf '○' ;; *)       printf '?' ;;
      esac ;;
  esac
}

# tmux colour name per state — used by status.sh, the window glyph and menus.
bs_color() {                                      # STATE
  case "${1:-}" in
    waiting) printf 'colour214' ;;  # amber  — needs you
    error)   printf 'colour203' ;;  # red
    working) printf 'colour39'  ;;  # blue
    done)    printf 'colour78'  ;;  # green
    stopped) printf 'colour245' ;;
    exited)  printf 'colour240' ;;
    idle)    printf 'colour244' ;;
    *)       printf 'colour244' ;;
  esac
}

# ANSI SGR per state — used by the fzf board and feed (which render with --ansi).
bs_ansi() {                                       # STATE
  case "${1:-}" in
    waiting) printf '\033[38;5;214m' ;;
    error)   printf '\033[38;5;203m' ;;
    working) printf '\033[38;5;39m'  ;;
    done)    printf '\033[38;5;78m'  ;;
    stopped) printf '\033[38;5;245m' ;;
    exited)  printf '\033[38;5;240m' ;;
    idle)    printf '\033[38;5;244m' ;;
    *)       printf '\033[38;5;244m' ;;
  esac
}
# shellcheck disable=SC2034  # consumed by scripts that source this file
BS_RESET=$'\033[0m'
# shellcheck disable=SC2034
BS_BOLD=$'\033[1m'
# shellcheck disable=SC2034
BS_DIM=$'\033[2m'

# Severity for the window mirror: waiting > error > working > done > idle.
bs_severity() {                                   # STATE
  case "${1:-}" in
    waiting) printf '5' ;; error) printf '4' ;; working) printf '3' ;;
    done)    printf '2' ;; stopped) printf '2' ;; idle) printf '1' ;;
    *)       printf '0' ;;
  esac
}

# Human label for an agent type, for notification titles.
bs_agent_label() {                                # TYPE
  case "${1:-}" in
    claude)   printf 'Claude' ;;
    opencode) printf 'opencode' ;;
    codex)    printf 'Codex' ;;
    gemini)   printf 'Gemini' ;;
    cursor)   printf 'Cursor' ;;
    copilot)  printf 'Copilot' ;;
    droid)    printf 'Droid' ;;
    '')       printf 'Agent' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# ------------------------------------------------------------------ platform

# darwin | wsl | linux | other
bs_platform() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf 'darwin' ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then printf 'wsl'; else printf 'linux'; fi ;;
    *) printf 'other' ;;
  esac
}

# Detach a command completely: no controlling terminal, all three fds closed.
# A hook that leaves stdout open makes the *agent* wait for the pipe to close,
# which looks exactly like a hung hook.
bs_detach() {                                     # COMMAND [ARGS...]
  if bs_have setsid; then
    setsid "$@" </dev/null >/dev/null 2>&1 &
  else
    nohup "$@" </dev/null >/dev/null 2>&1 &
  fi
  return 0
}

# ------------------------------------------------------- worktree helpers

wt_sanitize() { printf '%s' "$1" | sed 's#[/\\]#-#g'; }      # mirrors worktrunk's `sanitize`

# Signal launch.sh to re-open the bonsai menu, then exit cleanly. Used on cancel
# (fzf abort / empty prompt / key-to-close) so backing out returns to the menu.
wt_back() { tmx set-option -g @bonsai-back 1; exit 0; }

wt_agent() {
  local a; a=$(tmx show-option -gqv @bonsai-agent)
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
  tmx has-session -t "$S" 2>/dev/null || tmx new-session -d -s "$S" -c "$2"
  printf '%s' "$S"
}
