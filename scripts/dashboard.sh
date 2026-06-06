#!/usr/bin/env bash
# Live-refresh jump board: every open pane (agent or plain shell) plus every
# worktree that has no pane of its own, where one keypress jumps to the EXACT
# session/window/pane it shows. Launched through launch.sh (popup) like
# switch.sh/list.sh. No daemon: snapshots on open, re-renders on a timer, dies
# on close.
#
# Two properties make the jump reliable:
#   * CWD-independent — panes belong to many different repos, so each pane's
#     worktree is resolved by running git *in that pane's own directory* (never
#     the launcher's repo), and the resolved worktree path is carried inside the
#     row so a jump never re-resolves a branch against the wrong repo.
#   * Field-safe — rows are joined with the ASCII Unit Separator (0x1f) rather
#     than a tab. tmux paths/branches never contain it, and unlike tab (an IFS
#     whitespace char) an *empty* field between two separators is preserved by
#     `read`, so rows with blank cells (offline worktrees have no pane id) don't
#     shift their columns and mis-route the jump.
set -uo pipefail
. "$(dirname "$0")/_lib.sh"

refresh=$(tmux show-option -gqv @bonsai-refresh); refresh=${refresh:-2}
# Single-key labels, 1-9 then a-z, skipping r (refresh) and q (quit).
labels='123456789abcdefghijklmnopstuvwxyz'
US=$'\x1f'                                     # row field separator (non-whitespace)

PFMT="#{pane_id}${US}#{session_name}${US}#{window_id}${US}#{window_name}${US}#{pane_current_path}${US}#{@agent_state}${US}#{@agent_state_ts}"
WFMT=$'#{window_id}\t#{session_name}\t#{window_name}'

# Glyphs are padded to two terminal columns so the emoji rows (2 cells) and the
# text rows (1 cell + a space) line up under the same column.
glyph_of() {
  case "$1" in
    working) printf '🔄' ;;
    waiting) printf '💬' ;;
    done)    printf '✅' ;;
    error)   printf '❗' ;;
    idle)    printf '— '  ;;
    shell)   printf '▫ '  ;;
    offline) printf '⏸ '  ;;
    *)       printf '· '  ;;
  esac
}
# Sort priority: waiting -> error -> done -> working -> idle -> shell -> offline.
rank_of() {
  case "$1" in
    waiting) echo 0 ;; error) echo 1 ;; done) echo 2 ;;
    working) echo 3 ;; idle)  echo 4 ;; shell) echo 5 ;;
    offline) echo 6 ;; *) echo 5 ;;
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
trunc() {                                     # string width -> truncated to width (ASCII-safe padding)
  local s="$1" n="$2"
  if [ "${#s}" -gt "$n" ]; then printf '%s' "${s:0:n}"; else printf '%s' "$s"; fi
}
emit_row() { local IFS="$US"; printf '%s\n' "$*"; }   # join args with US, even empty ones

# Resolve a pane's directory to (toplevel, display-name, branch), cached by path
# within one gather pass so repeated paths cost a single git call. Sets globals
# G_TOP (worktree root, '' if not a repo), G_NAME (label), G_BRANCH ('' if detached).
gitcache=''
resolve() {
  local c="$1" line out top br
  line=$(awk -F"$US" -v c="$c" '$1==c{print;exit}' <<<"$gitcache")
  if [ -z "$line" ]; then
    out=$(git -C "$c" rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null)
    top=${out%%$'\n'*}
    br=${out#*$'\n'}; [ "$br" = "$out" ] && br=''      # no 2nd line => no branch
    if [ -n "$top" ]; then
      if [ -z "$br" ] || [ "$br" = HEAD ]; then G_NAME=${top##*/}; br=''
      else G_NAME=$(wt_sanitize "$br"); fi
    else
      G_NAME=${c##*/}; top=''
    fi
    line="$c$US$top$US$G_NAME$US$br"
    gitcache="$gitcache$line"$'\n'
  fi
  IFS="$US" read -r _ G_TOP G_NAME G_BRANCH <<<"$line"
}

# Print one row per open pane + per worktree that has no pane.
# Fields: rank glyph state worktree location age kind pid wid sess branch path
gather() {
  now=$(date +%s)
  local covered=$'\n' repotops=$'\n'

  # 1) every open pane (precise) — agent or plain shell — jumped to by exact id.
  while IFS="$US" read -r pid sname wid wname cpath st ts; do
    [ -n "$pid" ] || continue
    resolve "$cpath"
    local wt state glyph rank loc
    wt=$G_NAME
    if [ -n "${st:-}" ]; then state=$st; else state=shell; fi
    rank=$(rank_of "$state"); glyph=$(glyph_of "$state")
    loc="$sname:$wname $pid"
    if [ -n "$G_TOP" ]; then
      case "$covered"  in *$'\n'"$G_TOP"$'\n'*) ;; *) covered="$covered$G_TOP"$'\n'  ;; esac
      case "$repotops" in *$'\n'"$G_TOP"$'\n'*) ;; *) repotops="$repotops$G_TOP"$'\n' ;; esac
    fi
    emit_row "$rank" "$glyph" "$state" "$wt" "$loc" "$(fmt_age "$ts")" \
             pane "$pid" "$wid" "$sname" "$G_BRANCH" "$cpath"
  done <<EOF
$(tmux list-panes -a -F "$PFMT")
EOF

  # 2) worktrees (across every repo that has a pane) with no pane of their own:
  #    live session -> idle, linked window -> idle, otherwise offline.
  local allwt
  allwt=$(
    while IFS= read -r top; do
      [ -n "$top" ] || continue
      git -C "$top" worktree list --porcelain 2>/dev/null | awk '
        /^worktree /{w=$2}
        /^branch /{b=$2; sub("refs/heads/","",b); print b"\t"w}'
    done <<EOF2
$repotops
EOF2
  )
  while IFS=$'\t' read -r b p; do
    [ -n "$b" ] || continue
    case "$covered" in *$'\n'"$p"$'\n'*) continue ;; esac      # path already has a pane
    local n; n=$(wt_sanitize "$b")
    if tmux has-session -t "=$n" 2>/dev/null; then
      emit_row 4 "$(glyph_of idle)" idle "$n" "$n" '—' sess '' '' "$n" "$b" "$p"
    else
      local win wid wsess
      win=$(tmux list-windows -a -F "$WFMT" | awk -F'\t' -v n="$n" '$3==n{print $1"\t"$2; exit}')
      if [ -n "$win" ]; then
        IFS=$'\t' read -r wid wsess <<<"$win"
        emit_row 4 "$(glyph_of idle)" idle "$n" "$wsess:$n" '—' win '' "$wid" "$wsess" "$b" "$p"
      else
        emit_row 6 "$(glyph_of offline)" offline "$n" '—' '—' offline '' '' '' "$b" "$p"
      fi
    fi
  done <<EOF
$(printf '%s\n' "$allwt" | awk -F'\t' 'NF && !seen[$2]++')
EOF
}

jump() {
  local rank glyph state wt loc age kind pid wid sess branch path S
  IFS="$US" read -r rank glyph state wt loc age kind pid wid sess branch path <<<"$1"
  case "$kind" in
    # Attach to the session first, THEN pick window/pane, so the client lands on
    # exactly this pane regardless of where it was before.
    pane)    tmux switch-client -t "$sess"
             tmux select-window -t "$wid" 2>/dev/null
             tmux select-pane   -t "$pid" 2>/dev/null ;;
    sess)    tmux switch-client -t "$sess" ;;
    win)     tmux switch-client -t "$sess"
             tmux select-window -t "$wid" 2>/dev/null ;;
    offline) S=$(wt_ensure_session "$branch" "$path")        # path is repo-correct (carried in the row)
             tmux switch-client -t "$S" ;;
  esac
}

# Debug: snapshot the rows once and exit, without driving any client. Handy for
# verifying attribution/jump targets outside the popup (fields shown US-delimited).
if [ "${1:-}" = --dump ]; then gather | sort -n; exit 0; fi

while :; do
  rows=$(gather | sort -n)
  printf '\033[2J\033[H'
  printf ' 🌳 bonsai dashboard      [1-9 a-z] jump   [r] refresh   [q] back\n'
  printf ' %s  %s %-8s  %-24s  %-22s  %s\n' ' ' '  ' state worktree location age
  printf ' ───────────────────────────────────────────────────────────────────────────\n'
  n=0; ROWS=()
  if [ -n "$rows" ]; then
    while IFS= read -r line; do
      n=$(( n + 1 )); ROWS[$n]="$line"
      lbl=${labels:$(( n - 1 )):1}
      IFS="$US" read -r rank glyph state wt loc age kind pid wid sess branch path <<<"$line"
      printf ' %s  %s %-8s  %-24s  %-22s  %s\n' "${lbl:-·}" "$glyph" "$state" \
             "$(trunc "$wt" 24)" "$(trunc "$loc" 22)" "$age"
    done <<EOF
$rows
EOF
  else
    printf '   (no panes or worktrees)\n'
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
