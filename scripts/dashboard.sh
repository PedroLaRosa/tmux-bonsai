#!/usr/bin/env bash
# Live-refresh jump board: every worktree (live + offline) and every agent pane
# with its state, where one keypress jumps to the exact session/window/pane.
# Launched through launch.sh (popup) like switch.sh/list.sh. No daemon: it
# snapshots on open, re-renders on a timer while open, and dies on close.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"

refresh=$(tmux show-option -gqv @bonsai-refresh); refresh=${refresh:-2}
# Single-key labels, 1-9 then a-z, skipping r (refresh) and q (quit).
labels='123456789abcdefghijklmnopstuvwxyz'

PFMT=$'#{pane_id}\t#{session_name}\t#{window_id}\t#{window_name}\t#{pane_current_path}\t#{@agent_state}\t#{@agent_state_ts}'
WFMT=$'#{window_id}\t#{session_name}\t#{window_name}'

glyph_of() {
  case "$1" in
    working) printf '🔄' ;;
    waiting) printf '💬' ;;
    done)    printf '✅' ;;
    error)   printf '❗' ;;
    idle)    printf '—'  ;;
    offline) printf '⏸'  ;;
    *)       printf '·'  ;;
  esac
}
# Sort priority: waiting -> error -> done -> working -> idle -> offline.
rank_of() {
  case "$1" in
    waiting) echo 0 ;; error) echo 1 ;; done) echo 2 ;;
    working) echo 3 ;; idle)  echo 4 ;; offline) echo 5 ;; *) echo 6 ;;
  esac
}
fmt_age() {                                   # epoch -> 5s / 2m / 1h ; — if blank
  local ts="$1" d
  [ -n "$ts" ] || { printf '—'; return; }
  d=$(( now - ts )); [ "$d" -lt 0 ] && d=0
  if   [ "$d" -lt 60 ];   then printf '%ss' "$d"
  elif [ "$d" -lt 3600 ]; then printf '%sm' "$(( d / 60 ))"
  else                         printf '%sh' "$(( d / 3600 ))"
  fi
}
# Pane -> worktree name. pane_current_path is ground truth (it's the dir the
# agent actually works in), so the longest worktree path that prefixes it wins.
# Fall back to window-name then session-name (bonsai names them wt_sanitize(branch)):
# a window-worktree lives as a window inside some *other* session, so window name
# must outrank session name or it'd be misattributed to the host session's worktree.
match_wt() {
  local _s="$1" _w="$2" _c="$3" b p n winhit='' seshit='' pathhit='' plen=-1
  while IFS=$'\t' read -r b p; do
    [ -n "$b" ] || continue
    n=$(wt_sanitize "$b")
    [ "$n" = "$_w" ] && winhit="$n"
    [ "$n" = "$_s" ] && seshit="$n"
    case "$_c" in
      "$p"|"$p"/*) [ "${#p}" -gt "$plen" ] && { pathhit="$n"; plen=${#p}; } ;;
    esac
  done <<EOF
$wts
EOF
  if   [ -n "$pathhit" ]; then printf '%s' "$pathhit"
  elif [ -n "$winhit"  ]; then printf '%s' "$winhit"
  elif [ -n "$seshit"  ]; then printf '%s' "$seshit"
  fi
}
emit_row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }

# Print one tab-separated row per agent pane + per idle/offline worktree.
# Fields: rank glyph state worktree where age kind pane_id window_id session branch
gather() {
  now=$(date +%s)
  wts=$(git worktree list --porcelain 2>/dev/null | awk '
    /^worktree /{w=$2}
    /^branch /{b=$2; sub("refs/heads/","",b); print b"\t"w}')
  covered=' '

  # 1) agent panes (precise) — one row each, jumped to by exact pane id.
  while IFS=$'\t' read -r pid sname wid wname cpath st ts; do
    [ -n "${st:-}" ] || continue
    local wtname; wtname=$(match_wt "$sname" "$wname" "$cpath"); wtname=${wtname:-$sname}
    covered="$covered$wtname "
    emit_row "$(rank_of "$st")" "$(glyph_of "$st")" "$st" "$wtname" "[pane]" \
             "$(fmt_age "$ts")" pane "$pid" "$wid" "$sname" ''
  done <<EOF
$(tmux list-panes -a -F "$PFMT")
EOF

  # 2) worktrees without an agent pane: live -> idle, otherwise offline.
  while IFS=$'\t' read -r b p; do
    [ -n "$b" ] || continue
    local n; n=$(wt_sanitize "$b")
    case "$covered" in *" $n "*) continue ;; esac
    if tmux has-session -t "=$n" 2>/dev/null; then
      emit_row 4 "$(glyph_of idle)" idle "$n" "[sess]" '—' sess '' '' "$n" "$b"
    else
      local win; win=$(tmux list-windows -a -F "$WFMT" | awk -F'\t' -v n="$n" '$3==n{print $1"\t"$2; exit}')
      if [ -n "$win" ]; then
        local wid wsess; IFS=$'\t' read -r wid wsess <<<"$win"
        emit_row 4 "$(glyph_of idle)" idle "$n" "[win]" '—' win '' "$wid" "$wsess" "$b"
      else
        emit_row 5 "$(glyph_of offline)" offline "$n" "[git]" '—' offline '' '' '' "$b"
      fi
    fi
  done <<EOF
$wts
EOF
}

jump() {
  local rank glyph state wt where age kind pid wid sess branch path S
  IFS=$'\t' read -r rank glyph state wt where age kind pid wid sess branch <<<"$1"
  case "$kind" in
    pane)    tmux select-window -t "$wid" 2>/dev/null
             tmux select-pane   -t "$pid" 2>/dev/null
             tmux switch-client -t "$sess" ;;
    sess)    tmux switch-client -t "$sess" ;;
    win)     tmux select-window -t "$wid" 2>/dev/null
             tmux switch-client -t "$sess" ;;
    offline) path=$(wt_path_of "$branch")
             S=$(wt_ensure_session "$branch" "$path")
             tmux switch-client -t "$S" ;;
  esac
}

while :; do
  rows=$(gather | sort -n)
  printf '\033[2J\033[H'
  printf ' 🌳 bonsai dashboard      [1-9 a-z] jump   [r] refresh   [q] back\n'
  printf ' %s  %s %-8s  %-22s  %-6s  %s\n' ' ' ' ' state worktree where age
  printf ' ─────────────────────────────────────────────────────────────\n'
  n=0; ROWS=()
  if [ -n "$rows" ]; then
    while IFS= read -r line; do
      n=$(( n + 1 )); ROWS[$n]="$line"
      lbl=${labels:$(( n - 1 )):1}
      IFS=$'\t' read -r rank glyph state wt where age kind pid wid sess branch <<<"$line"
      printf ' %s  %s %-8s  %-22s  %-6s  %s\n' "${lbl:-·}" "$glyph" "$state" "$wt" "$where" "$age"
    done <<EOF
$rows
EOF
  else
    printf '   (no worktrees or agents)\n'
  fi
  printf '\n'

  k=''; IFS= read -t "$refresh" -rsn1 k || true
  case "$k" in
    r)     continue ;;
    q)     wt_back ;;
    $'\e') wt_back ;;
    '')    continue ;;
    *)     pre=${labels%%"$k"*}                 # 1-based position of k in labels (portable; BSD expr lacks `index`)
           if [ "$pre" != "$labels" ]; then
             idx=$(( ${#pre} + 1 ))
             [ "$idx" -le "$n" ] && { jump "${ROWS[$idx]}"; exit 0; }
           fi ;;
  esac
done
