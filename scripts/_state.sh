#!/usr/bin/env bash
# The state store: tmux pane options.
#
# Pane options die with the pane, are readable from any status-line format and
# need no daemon, which is why they are the single source of truth (plan §4.2).
# This file owns every read and write of them, plus the events log, the per-pane
# lock and the settings file.
#
# Reading them back has three tmux quirks, all verified on 3.4 (see
# tests/state.bats):
#   * format output escapes control bytes — a 0x1F separator comes back as the
#     four characters `\037`, newline and tab come back as `_`;
#   * a backslash is *not* escaped, so `\037` in the output is ambiguous with a
#     value that literally contains those characters. st_load therefore checks
#     the field count and falls back to one read per field when it disagrees;
#   * non-ASCII survives only if the client's LC_CTYPE is UTF-8 (bs_fix_locale).

# shellcheck source=scripts/_lib.sh
. "${BONSAI_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)}/_lib.sh"

# The pane snapshot: one line per field as `VARNAME  #{format}`. Deriving both
# the format string and the variable list from a single table means they cannot
# drift apart. Free-text fields come last on purpose — see the count check in
# st_load.
ST_MAP='ST_state #{@agent_state}
ST_state_ts #{@agent_state_ts}
ST_seq #{@agent_seq}
ST_type #{@agent_type}
ST_seen_ts #{@agent_seen_ts}
ST_notify_id #{@agent_notify_id}
ST_notified_ts #{@agent_notified_ts}
ST_title_state #{@agent_title_state}
ST_launch_ts #{@agent_launch_ts}
ST_children #{@agent_children}
ST_agent_session #{@agent_session}
ST_model #{@agent_model}
ST_ctx #{@agent_ctx}
ST_session_name #{session_name}
ST_window_index #{window_index}
ST_pane_index #{pane_index}
ST_pane_pid #{pane_pid}
ST_pane_active #{pane_active}
ST_window_active #{window_active}
ST_session_attached #{session_attached}
ST_pane_tty #{pane_tty}
ST_window_id #{window_id}
ST_window_name #{window_name}
ST_cwd #{pane_current_path}
ST_transcript #{@agent_transcript}
ST_tool #{@agent_tool}
ST_ask #{@agent_ask}
ST_prompt #{@agent_prompt}
ST_msg #{@agent_msg}
ST_title #{pane_title}'

# The separator we send (0x1F) and the four characters tmux renders it back as.
ST_SEP_RAW=$(printf '\037')
ST_SEP_OUT='\037'

ST_FIELD_VARS=$(printf '%s\n' "$ST_MAP" | awk 'NF{print $1}')
ST_FMT=$(printf '%s\n' "$ST_MAP" | awk 'NF{print $2}' | tr '\n' "$ST_SEP_RAW")
ST_FMT=${ST_FMT%"$ST_SEP_RAW"}
ST_NFIELDS=$(printf '%s\n' "$ST_MAP" | awk 'NF{n++}END{print n+0}')

# Split a rendered snapshot line on the escaped separator. Pure bash: no forks,
# and unlike word splitting it keeps empty fields, including trailing ones.
st_split() {                                      # LINE -> ST_VALS[]
  local rest="${1:-}" v
  ST_VALS=()
  while :; do
    case "$rest" in
      *"$ST_SEP_OUT"*)
        v="${rest%%"$ST_SEP_OUT"*}"
        rest="${rest#*"$ST_SEP_OUT"}"
        ST_VALS+=("$v")
        ;;
      *)
        ST_VALS+=("$rest")
        break
        ;;
    esac
  done
}

# st_load PANE — sets ST_* for the pane. Returns 1 if the pane is gone.
st_load() {                                       # PANE
  local pane="$1" line var i
  line=$(tmx display-message -p -t "$pane" "$ST_FMT" 2>/dev/null) || return 1
  [ -n "$line" ] || return 1

  st_split "$line"
  if [ "${#ST_VALS[@]}" -ne "$ST_NFIELDS" ]; then
    # Some value contained the escaped separator literally (a backslash is not
    # itself escaped by tmux, so `\037` in the output is ambiguous). Pay for one
    # read per field rather than mis-assign every field after it.
    st_load_slow "$pane"
    return $?
  fi

  i=0
  for var in $ST_FIELD_VARS; do
    eval "$var=\${ST_VALS[$i]}"
    i=$((i + 1))
  done
  st_defaults
  return 0
}

st_load_slow() {                                  # PANE
  local pane="$1" var fmt
  tmx display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2034  # $fmt is referenced through the eval below
  while read -r var fmt; do
    [ -n "$var" ] || continue
    eval "$var=\$(tmx display-message -p -t \"\$pane\" \"\$fmt\" 2>/dev/null)"
  done <<EOF
$ST_MAP
EOF
  st_defaults
  return 0
}

st_defaults() {
  [ -n "${ST_state:-}" ]     || ST_state=unknown
  [ -n "${ST_state_ts:-}" ]  || ST_state_ts=0
  [ -n "${ST_seq:-}" ]       || ST_seq=0
  [ -n "${ST_seen_ts:-}" ]   || ST_seen_ts=0
  [ -n "${ST_children:-}" ]  || ST_children=0
  [ -n "${ST_notified_ts:-}" ] || ST_notified_ts=0
  [ -n "${ST_launch_ts:-}" ] || ST_launch_ts=0
  case "$ST_state_ts"    in *[!0-9]*) ST_state_ts=0 ;; esac
  case "$ST_seq"         in *[!0-9]*) ST_seq=0 ;; esac
  case "$ST_seen_ts"     in *[!0-9]*) ST_seen_ts=0 ;; esac
  case "$ST_children"    in *[!0-9]*) ST_children=0 ;; esac
  case "$ST_notified_ts" in *[!0-9]*) ST_notified_ts=0 ;; esac
  case "$ST_launch_ts"   in *[!0-9]*) ST_launch_ts=0 ;; esac
}

# st_write PANE KEY VALUE [KEY VALUE ...] — one tmux invocation for the whole
# event, then a status refresh so the segment updates without waiting for
# status-interval.
st_write() {                                      # PANE KEY VALUE ...
  local pane="$1"; shift
  [ $# -ge 2 ] || return 0
  local args=() first=1
  while [ $# -ge 2 ]; do
    if [ "$first" -eq 1 ]; then first=0; else args+=(';'); fi
    args+=(set-option -p -t "$pane" "$1" "$(bs_argv_safe "$2")")
    shift 2
  done
  tmx "${args[@]}" 2>/dev/null || return 1
  # Separate call, status ignored: `refresh-client -S` fails with "no current
  # client" on a server nobody is attached to (a headless test server, or a
  # detached session), which must not make the write look like it failed.
  tmx refresh-client -S 2>/dev/null || true
  return 0
}

# Same, on a window rather than a pane.
st_write_window() {                               # WINDOW KEY VALUE ...
  local win="$1"; shift
  [ $# -ge 2 ] || return 0
  local args=() first=1
  while [ $# -ge 2 ]; do
    if [ "$first" -eq 1 ]; then first=0; else args+=(';'); fi
    args+=(set-option -w -t "$win" "$1" "$(bs_argv_safe "$2")")
    shift 2
  done
  tmx "${args[@]}" 2>/dev/null
  return $?
}

# Mirror the most severe live pane state onto the window, so a one-line
# window-status-format glyph keeps working (plan §4.7).
#
# The mirror deliberately does *not* reuse @agent_state. tmux resolves a user
# option pane-first even when the target is a window, so a window-level
# @agent_state is permanently shadowed by the active pane's own value and the
# glyph would show the wrong pane's state. @agent_window_state has no pane-level
# counterpart, so it always resolves to the mirror. (Verified on 3.4; see
# tests/state.bats "window mirror".)
st_mirror_window() {                              # PANE
  local pane="$1" win best='' best_sev=-1 line st sev
  win=$(tmx display-message -p -t "$pane" '#{window_id}' 2>/dev/null) || return 0
  [ -n "$win" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    st="$line"
    sev=$(bs_severity "$st")
    if [ "$sev" -gt "$best_sev" ]; then best_sev="$sev"; best="$st"; fi
  done <<EOF
$(tmx list-panes -t "$win" -F '#{@agent_state}' 2>/dev/null)
EOF
  st_write_window "$win" @agent_window_state "${best:-}"
}

# ------------------------------------------------------------------- locking

# `flock` is not on macOS, so use the portable mkdir lock with a stale-holder
# check: the pid inside the directory is probed with kill -0.
st_lock() {                                       # PANE [TIMEOUT_SECONDS]
  local pane="$1" timeout="${2:-3}" dir tries=0 max holder
  dir="$(bs_state_dir)/locks/$(printf '%s' "$pane" | tr -cd 'A-Za-z0-9_%-')"
  mkdir -p "$(dirname "$dir")" 2>/dev/null || true
  max=$((timeout * 50))                           # 20 ms per try
  while :; do
    if mkdir "$dir" 2>/dev/null; then
      printf '%s' "$$" > "$dir/pid" 2>/dev/null
      ST_LOCK_DIR="$dir"
      return 0
    fi
    holder=$(cat "$dir/pid" 2>/dev/null)
    if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
      rm -rf "$dir" 2>/dev/null                   # holder died mid-transition
      continue
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge "$max" ]; then return 1; fi
    sleep 0.02 2>/dev/null || sleep 1
  done
}

st_unlock() {
  [ -n "${ST_LOCK_DIR:-}" ] || return 0
  rm -rf "$ST_LOCK_DIR" 2>/dev/null
  ST_LOCK_DIR=''
}

# ---------------------------------------------------------------- sequencing

# Monotonic per pane. Subagent bursts fire hooks in parallel, so the reducer
# takes the lock, bumps, and rejects anything that arrives with an older seq.
st_next_seq() {                                   # PANE
  local cur
  cur=$(bs_popt "$1" @agent_seq 0)
  case "$cur" in *[!0-9]*) cur=0 ;; esac
  printf '%s' "$((cur + 1))"
}

# ---------------------------------------------------------------- event log

ST_EVENTS_MAX=1048576                             # 1 MB, then rotate

st_events_file() { printf '%s/events.jsonl' "$(bs_state_dir)"; }

# Append one pre-built JSON object. The log is 0600: it carries prompts.
ev_append() {                                     # JSON_LINE
  local f d size
  d=$(bs_state_dir)
  [ -d "$d" ] || { mkdir -p "$d" 2>/dev/null || return 0; chmod 700 "$d" 2>/dev/null || true; }
  f="$d/events.jsonl"
  if [ ! -e "$f" ]; then
    : > "$f" 2>/dev/null || return 0
    chmod 600 "$f" 2>/dev/null || true
  fi
  size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -ge "$ST_EVENTS_MAX" ]; then
    mv -f "$f" "$d/events.1.jsonl" 2>/dev/null || true
    : > "$f" 2>/dev/null || return 0
    chmod 600 "$f" 2>/dev/null || true
  fi
  printf '%s\n' "$1" >> "$f" 2>/dev/null || true
}

# ev_json k v k v ... — build one JSON object. Values are strings unless the
# key is suffixed with `#` (then it is emitted as a bare number) or `~` (raw
# JSON, for the nested notify object).
ev_json() {
  local out='{' first=1 k v kind
  while [ $# -ge 2 ]; do
    k="$1"; v="$2"; shift 2
    kind=string
    case "$k" in
      *'#') kind=number; k="${k%\#}" ;;
      *'~') kind=raw;    k="${k%\~}" ;;
    esac
    [ -n "$v" ] || { [ "$kind" = string ] || continue; }
    if [ "$first" -eq 1 ]; then first=0; else out="$out,"; fi
    case "$kind" in
      number) case "$v" in ''|*[!0-9.-]*) v=0 ;; esac; out="$out$(bs_json "$k"):$v" ;;
      raw)    out="$out$(bs_json "$k"):$v" ;;
      *)      out="$out$(bs_json "$k"):$(bs_json "$v")" ;;
    esac
  done
  printf '%s}' "$out"
}

# ------------------------------------------------------------------ settings

# Runtime toggles are written here *and* applied live. Precedence at load time
# is: .tmux.conf (already set when the plugin loads, so it wins) > this file >
# built-in defaults — see bonsai_default in bonsai.tmux.
st_settings_file() { printf '%s/settings.tmux' "$(bs_config_dir)"; }

settings_get() {                                  # OPT
  tmx show-option -gqv "$1" 2>/dev/null
}

settings_set() {                                  # OPT VALUE
  local opt="$1" val="${2:-}" f d tmp esc
  f=$(st_settings_file); d=$(dirname "$f")
  mkdir -p "$d" 2>/dev/null || return 1
  [ -e "$f" ] || : > "$f"
  tmp="$f.tmp.$$"
  grep -v "^set -g ${opt} " "$f" > "$tmp" 2>/dev/null || : > "$tmp"
  esc=$(printf '%s' "$val" | sed "s/'/'\\\\''/g")
  printf "set -g %s '%s'\n" "$opt" "$esc" >> "$tmp"
  mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  tmx set-option -g "$opt" "$(bs_argv_safe "$val")" 2>/dev/null
  tmx refresh-client -S 2>/dev/null || true
}

settings_unset() {                                # OPT
  local opt="$1" f tmp
  f=$(st_settings_file)
  [ -e "$f" ] || return 0
  tmp="$f.tmp.$$"
  grep -v "^set -g ${opt} " "$f" > "$tmp" 2>/dev/null || : > "$tmp"
  mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

settings_reset() {
  local f; f=$(st_settings_file)
  [ -e "$f" ] && rm -f "$f"
  return 0
}

# Is this option pinned in tmux.conf (i.e. set before the plugin loaded)?
# The menu labels such toggles so a user is not confused when their change
# reverts on the next reload.
settings_pinned() {                               # OPT
  local pinned
  pinned=$(bs_opt @bonsai-pinned "")
  case " $pinned " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
