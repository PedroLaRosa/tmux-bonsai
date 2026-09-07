#!/usr/bin/env bash
# Shared pane-state helpers; all tmux calls use the originating server socket.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

bonsai_pane_opt() {
  local value
  value=$(tmx show-option -pqv -t "$1" "$2" 2>/dev/null) || return 1
  printf '%s' "${value:-${3:-}}"
}

# Values in the state store cannot contain this separator. A single format read
# also gives callers a consistent snapshot of an atomic reducer write.
bonsai_snapshot() {
  local pane=$1 key format='' sep=$'\034' snapshot local_state
  local keys='state state_ts seq type prompt msg ask tool session transcript seen_ts notified_ts title_state title_ts hook_ts children child_ids parent_done source_seq'
  for key in $keys; do format="${format}#{@agent_${key}}${sep}"; done
  format="${format}#{pane_id}${sep}#{session_name}${sep}#{window_name}${sep}#{pane_current_path}${sep}#{window_id}${sep}#{pane_current_command}${sep}#{pane_pid}"
  snapshot=$(tmx display-message -p -t "$pane" "$format" 2>/dev/null | jq -Rc --arg keys "$keys pane session_name window_name cwd window_id command pid" '
    split("\u001c") as $values | ($keys | split(" ")) as $keys |
    reduce range(0; $keys | length) as $i ({}; .[$keys[$i]] = ($values[$i] // "")) |
    .state = (if .state == "" then "unknown" else .state end) |
    .child_ids = (.child_ids | fromjson? // []) |
    .parent_done = (.parent_done | fromjson? // null) |
    . as $s | reduce ["state_ts", "seq", "seen_ts", "notified_ts", "title_ts", "hook_ts", "children", "source_seq"][] as $k
      ($s; .[$k] = (.[$k] | tonumber? // 0))') || return 1
  [ -n "$snapshot" ] || return 1
  # The first event on a shell may inherit a sibling's window mirror. Preserve
  # legacy local markers, but never treat that inherited value as pane state.
  if printf '%s' "$snapshot" | jq -e '.type == "" and .seq == 0' >/dev/null; then
    local_state=$(tmx show-options -p -t "$pane" 2>/dev/null | awk '$1 == "@agent_state" {gsub(/"/, "", $2); print $2}')
    snapshot=$(printf '%s' "$snapshot" | jq -c --arg state "${local_state:-unknown}" '.state=$state')
  fi
  printf '%s\n' "$snapshot"
}

bonsai_window_mirror() {
  local window state
  window=$(tmx display-message -p -t "$1" '#{window_id}' 2>/dev/null) || return 0
  [ -n "$window" ] || return 0
  tmx wait-for -L "bonsai-window-${window}" 2>/dev/null || return 0
  state=$(tmx list-panes -t "$window" -F $'#{@agent_type}\t#{@agent_seq}\t#{@agent_state}' 2>/dev/null | awk -F '\t' '
    BEGIN { rank["waiting"]=8; rank["error"]=7; rank["working"]=6; rank["done"]=5; rank["stopped"]=4; rank["idle"]=3; rank["unknown"]=2; rank["exited"]=1 }
    ($1 != "" || $2 != "") && rank[$3]>best { best=rank[$3]; state=$3 } END { print state }')
  tmx set-option -w -t "$window" @agent_state "$state" 2>/dev/null || true
  tmx wait-for -U "bonsai-window-${window}" 2>/dev/null || true
}

# Store focus separately for each server: tty names can be reused by another
# server, and a detached client must never suppress its next notification.
bonsai_focus_file() {
  local socket token
  socket=${BONSAI_SOCKET:-${TMUX:-}}
  socket=${socket%%,*}
  token=$(printf '%s' "$socket" | cksum | awk '{print $1}')
  printf '%s/focused-clients-%s' "$(bonsai_state_dir)" "$token"
}

bonsai_is_focused() {
  local pane=$1 mode=${2:-strict} row tty active focused_file
  [ "$mode" != off ] || return 1
  focused_file=$(bonsai_focus_file)
  while IFS=$'\t' read -r tty active; do
    [ "$active" = "$pane" ] || continue
    [ "$mode" = attached ] && return 0
    [ -f "$focused_file" ] && grep -Fqx -- "$tty" "$focused_file" && return 0
  done < <(tmx list-clients -F $'#{client_tty}\t#{pane_id}' 2>/dev/null)
  return 1
}

# One JSON object per line, serialized with rotation so simultaneous agents
# cannot lose a decision while moving the previous 1 MB of history aside.
bonsai_log() {
  local pane=$1 event=$2 prev=$3 state=$4 category=${5:-} decision=${6:-} backend=${7:-} id=${8:-}
  local snapshot record dir file size
  snapshot=$(bonsai_snapshot "$pane") || return 0
  [ -n "$snapshot" ] || return 0
  record=$(printf '%s' "$snapshot" | jq -c --arg event "$event" --arg prev "$prev" --arg state "$state" \
    --arg category "$category" --arg decision "$decision" --arg backend "$backend" --arg id "$id" --argjson ts "$(date +%s)" '
    {ts:$ts,pane:.pane,session:.session_name,window:.window_name,cwd:.cwd,
     branch:(.cwd|split("/")|last),repo:(.cwd|split("/")|last),agent:.type,event:$event,
     prev:$prev,state:$state,ask:.ask,prompt:.prompt,summary:.msg} |
    if $decision != "" then .notify={category:$category,decision:$decision,backend:$backend,id:$id} else . end') || return 0
  dir=$(bonsai_state_dir); mkdir -p "$dir" || return 0
  file=$dir/events.jsonl
  tmx wait-for -L bonsai-events-log 2>/dev/null || return 0
  size=0; [ ! -f "$file" ] || size=$(wc -c < "$file")
  if [ "$size" -ge 1048576 ]; then mv -f "$file" "$dir/events.1.jsonl"; fi
  (umask 077; printf '%s\n' "$record" >> "$file")
  tmx wait-for -U bonsai-events-log 2>/dev/null || true
}
