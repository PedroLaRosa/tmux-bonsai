#!/usr/bin/env bash
set -uo pipefail
umask 077
. "$(dirname "$0")/_notify.sh"
state_dir=$(bonsai_state_dir)
server_key=$(bonsai_server_key)
ports="$state_dir/board-ports/$server_key"
views="$state_dir/board-views/$server_key"
mkdir -p "$ports" "$views"
self=$(printf '%q' "$BONSAI_SCRIPTS/board.sh")
# A board owns its view preferences and port registration, even with many clients.
board_header() {
 local counts waiting errors working done_unseen rest compact=off all sort
 local BONSAI_GLYPHS
 BONSAI_GLYPHS=$(bonsai_opt @bonsai-glyphs unicode)
 export BONSAI_GLYPHS
 if [ -n "${1:-}" ] && [ -f "$views/$1" ]; then read -r all sort compact < "$views/$1"; fi
 counts=$(tmx list-panes -a -F '#{@agent_type} #{@agent_state} #{@agent_state_ts} #{@agent_seen_ts}' 2>/dev/null | awk '
  $1!="" && $2=="waiting" {w++} $2=="error" {e++} $2=="working" {r++} $2=="done" && $3+0>$4+0 {d++}
  END {printf "%d %d %d %d",w,e,r,d}')
 read -r waiting errors working done_unseen rest <<< "$counts"
 printf '%s %s needs you · %s %s · %s %s working · %s %s done\n' "$(bonsai_glyph waiting)" "$waiting" "$(bonsai_glyph error)" "$errors" "$(bonsai_glyph working)" "$working" "$(bonsai_glyph 'done')" "$done_unseen"
 if [ "$compact" = on ]; then printf 'enter jump · ^r reply · ? help'; return; fi
 printf 'enter jump · ^r reply · ^y yes · ^u unread · ^x kill · ^e resume · ^n/^b needs you · ^a all · ^l sort · ? help'
 if [ "$(bonsai_opt @bonsai-notify on)" = on ] && ! bonsai_verification_current; then printf '\n! notifications unverified'; fi
}
view_rows() {
 local view=${1:-} all=off sort=state compact=off
 if [ -n "$view" ] && [ -f "$views/$view" ]; then read -r all sort compact < "$views/$view"; fi
 local args=(--rows --sort "$sort")
 [ "$all" != on ] || args+=(--all)
 [ "$compact" != on ] || args+=(--compact)
 "$BONSAI_SCRIPTS/list.sh" "${args[@]}"
}
case "${1:-}" in
 --ports-dir) printf '%s\n' "$ports"; exit;;
 --header) board_header; exit;;
 --rows)
  shift; if [ "${1:-}" = --view ]; then view_rows "${2:-}"; else exec "$BONSAI_SCRIPTS/list.sh" --rows "$@"; fi; exit;;
 --register)
  port=${2:-}; pid=${BONSAI_BOARD_PID:-${3:-}}
  case "$port:$pid" in *[!0-9:]*|:|*:) exit 2;; esac
  printf '%s %s\n' "$port" "${FZF_API_KEY:-}" > "$ports/$pid"; exit;;
 --refresh)
  for registration in "$ports"/*; do
   [ -f "$registration" ] || continue
   pid=${registration##*/}; [ -z "${2:-}" ] || [ "$pid" = "$2" ] || continue
   read -r port token < "$registration"
   case "$port:$pid" in *[!0-9:]*|:|*:) rm -f "$registration"; continue;; esac
   if ! kill -0 "$pid" 2>/dev/null || ! curl --silent --fail --max-time 0.2 \
    --request POST -H "X-API-Key: ${token:-}" --data-binary "reload($self --rows --view $pid)+refresh-preview+change-header($(board_header "$pid"))" "http://127.0.0.1:$port" >/dev/null 2>&1; then
    rm -f "$registration"
   fi
  done; exit;;
 --toggle-all|--cycle-sort)
  action=$1; pid=${2:-}; case "$pid" in ''|*[!0-9]*) exit 2;; esac
  all=off sort=state compact=off; [ ! -f "$views/$pid" ] || read -r all sort compact < "$views/$pid"
  if [ "$action" = --toggle-all ]; then if [ "$all" = on ]; then all=off; else all=on; fi
  else case "$sort" in state) sort=recent;; recent) sort=age;; *) sort=state;; esac; fi
  printf '%s %s %s\n' "$all" "$sort" "$compact" > "$views/$pid"; exit;;
 --navigate)
  pid=${2:-}; direction=${3:-next}; current=${4:-}; query=${5:-}
  action=$(view_rows "$pid" | fzf --filter "$query" --no-sort --ansi --delimiter $'\037' --nth '4..7' | awk -F '\037' -v current="$current" -v direction="$direction" '
   $1==current {selected=NR} $2 ~ /^\[0,/ {positions[++n]=NR}
   END {if(!n) exit; result=positions[1];
    if(direction=="previous") {result=positions[n]; for(i=n;i>0;i--) if(positions[i]<selected){result=positions[i];break}}
    else {for(i=1;i<=n;i++) if(positions[i]>selected){result=positions[i];break}}
    printf "pos(%d)",result}')
  if [ -n "$action" ] && [ -f "$ports/$pid" ]; then
   read -r port token < "$ports/$pid"
   curl --silent --fail --max-time 0.2 -H "X-API-Key: ${token:-}" --data-binary "$action" "http://127.0.0.1:$port" >/dev/null
  fi
  exit;;
 --preview)
  pane=${2:-}
  case "$pane" in worktree:*) printf 'Offline worktree: %s\nEnter opens a session.\n' "${pane#worktree:}"; exit;; esac
  # Preview reads only its pane; a second full process/git scan would compete
  # with the board reload on every pushed event.
  facts=$(tmx display-message -p -t "$pane" '#{pane_current_path}
#{@agent_type} · #{@agent_state} · since #{t:@agent_state_ts}
#{session_name}:#{window_index}.#{pane_index}
You: #{@agent_prompt}
Agent: #{@agent_msg}
Ask: #{@agent_ask}
Model: #{@agent_model} · context #{@agent_ctx}% · children #{@agent_children}') || exit 1
  cwd=${facts%%$'\n'*}; facts=${facts#*$'\n'}
  read -r key _ <<< "$(printf '%s' "$cwd" | cksum)"
  branch='' repo=$cwd
  entry="$state_dir/cache/branch-$key"
  if [ -f "$entry" ]; then
   { IFS= read -r _; IFS= read -r _; IFS= read -r branch; IFS= read -r repo; } < "$entry"
  fi
  printf '%s · %s\n%s\n\n' "$branch" "$repo" "$facts"
  "$BONSAI_SCRIPTS/capture.sh" "$pane"; exit;;
 --unread)
  pane=${2:-}; seen=$(tmx show-option -pqv -t "$pane" @agent_seen_ts); ts=$(tmx show-option -pqv -t "$pane" @agent_state_ts)
  if [ "${seen:-0}" -lt "${ts:-0}" ]; then exec "$BONSAI_SCRIPTS/ack.sh" "$pane"; else exec "$BONSAI_SCRIPTS/ack.sh" "$pane" --unread; fi;;
 --help)
  cat <<'HELP'
Agent board
  Enter    jump (watch mode stays open)
  Ctrl-R   reply, showing text and confirmation first
  Ctrl-Y   send y + Enter to a waiting agent, with confirmation
  Ctrl-U   toggle unread
  Ctrl-X   interrupt agent; optionally close its pane
  Ctrl-E   resume an exited agent
  Ctrl-N/B next/previous waiting row
  Ctrl-A   include shells and offline worktrees
  Ctrl-L   cycle state / most recent / oldest sorting
  Ctrl-P   toggle live preview
  Ctrl-O   notification settings
  Esc      return to menu (popup), quit (watch)

Waiting agents are oldest first so none is overlooked.
Search matches the agent, branch, location and preview.
HELP
  [ "${2:-}" != --pause ] || { printf '\n[Enter to return] '; IFS='' read -r _; }; exit;;
 --window|--toggle-window)
  session=$(tmx display-message -p '#{session_id}'); current=$(tmx display-message -p '#{window_id}')
  existing=$(tmx show-option -qv -t "$session" @bonsai-board-window-id)
  if [ -n "$existing" ] && tmx display-message -p -t "$existing" '#{window_id}' >/dev/null 2>&1; then
   if [ "$current" = "$existing" ]; then tmx kill-window -t "$existing"; else tmx select-window -t "$existing"; fi
  else
   window=$(tmx new-window -P -F '#{window_id}' -t "$session:" -n "$(bonsai_opt @bonsai-board-window bonsai)" "$self --watch") || exit 1
   tmx set-option -t "$session" @bonsai-board-window-id "$window"
  fi; exit;;
 --side|--toggle-side)
  window=$(tmx display-message -p '#{window_id}')
  existing=$(tmx show-option -wqv -t "$window" @bonsai-board-pane)
  if [ -n "$existing" ] && tmx display-message -p -t "$existing" '#{pane_id}' >/dev/null 2>&1; then
   tmx kill-pane -t "$existing"; tmx set-option -wu -t "$window" @bonsai-board-pane
  else
   pane=$(tmx split-window -h -l "$(bonsai_opt @bonsai-board-side-width 44)" -P -F '#{pane_id}' -t "$window" "$self --watch --compact") || exit 1
   tmx set-option -w -t "$window" @bonsai-board-pane "$pane"
  fi; exit;;
esac
watch=off compact=off
for arg in "$@"; do case "$arg" in --watch) watch=on;; --compact) compact=on;; *) echo "unknown board option: $arg" >&2; exit 2;; esac; done
command -v fzf >/dev/null || { echo 'The agent board requires fzf.' >&2; exit 1; }
export BONSAI_BOARD_PID=$$
FZF_API_KEY=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
export FZF_API_KEY
printf '%s %s %s\n' "$(bonsai_opt @bonsai-board-show-shells off)" "$(bonsai_opt @bonsai-board-sort state)" "$compact" > "$views/$$"
ticker=''
cleanup() { [ -z "$ticker" ] || kill "$ticker" 2>/dev/null || :; rm -f "$ports/$$" "$views/$$"; }
trap cleanup EXIT HUP INT TERM
reload="$self --rows --view $$"
script() { printf '%q' "$BONSAI_SCRIPTS/$1"; }
header=$(board_header "$$")
us=$'\037'
args=(--ansi --delimiter "$us" --with-nth '3..7' --nth '4..7' --layout reverse --no-sort --header "$header" --prompt 'agents> ')
args+=(--bind "ctrl-r:execute($(script reply.sh) {1})+reload($reload)")
args+=(--bind "ctrl-y:execute($(script reply.sh) {1} y --waiting-only)+reload($reload)")
args+=(--bind "ctrl-u:execute-silent($self --unread {1})+reload($reload)")
args+=(--bind "ctrl-x:execute($(script kill.sh) {1})+reload($reload)")
args+=(--bind "ctrl-e:execute($(script resume.sh) {1})+reload($reload)")
args+=(--bind "ctrl-a:execute-silent($self --toggle-all $$)+reload($reload)")
args+=(--bind "ctrl-l:execute-silent($self --cycle-sort $$)+reload($reload)")
args+=(--bind "ctrl-n:execute-silent($self --navigate $$ next {1} {q}),ctrl-b:execute-silent($self --navigate $$ previous {1} {q})")
args+=(--bind "ctrl-o:execute-silent($(script notify-menu.sh)),?:execute($self --help --pause)")
if [ "$compact" = on ]; then
 args+=(--with-nth '3,5,7' --header 'enter jump · ^r reply · ? help' --no-info)
else args+=(--preview "$self --preview {1}" --preview-window 'right:55%:wrap' --bind 'ctrl-p:toggle-preview'); fi
version=$(fzf --version | awk '{split($1,v,".");print v[1]*100+v[2]}')
if [ "${version:-0}" -ge 38 ]; then args+=(--track); fi
# New fzf releases can track the hidden pane ID even when ages/text change.
if fzf --help | grep -q -- '--id-nth'; then args+=(--id-nth 1); fi
if [ "${version:-0}" -ge 36 ] && command -v curl >/dev/null; then
 args+=(--listen 0 --bind "start:execute-silent($self --register \$FZF_PORT)")
 interval=$(bonsai_duration "$(bonsai_opt @bonsai-board-refresh 2)")
 ( while kill -0 "$BONSAI_BOARD_PID" 2>/dev/null; do sleep "$interval"; "$BONSAI_SCRIPTS/board.sh" --refresh "$BONSAI_BOARD_PID"; done ) </dev/null >/dev/null 2>&1 &
 ticker=$!
else
 args+=(--bind "ctrl-r:reload($reload),ctrl-n:down,ctrl-b:up" --header "$header
Install fzf >= 0.38 and curl for live refresh. Ctrl-R reloads.")
fi
if [ "$watch" = on ]; then args+=(--bind "enter:execute-silent($(script jump.sh) {1})"); fi
selected=$(view_rows "$$" | fzf "${args[@]}") || {
 [ "$watch" = on ] || wt_back; exit 0;
}
[ -z "$selected" ] || "$BONSAI_SCRIPTS/jump.sh" "${selected%%$'\037'*}"
