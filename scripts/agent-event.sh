#!/usr/bin/env bash
# The only writer of agent state. Hooks detach this script; it may do I/O.
source "$(cd "$(dirname "$0")" && pwd)/_state.sh"

agent=${1:-}; [ -n "$agent" ] || exit 0; shift
event=''; pane=${TMUX_PANE:-}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pane) pane=${2:-}; shift 2 ;;
    *) [ -z "$event" ] && event=$1; shift ;;
  esac
done
case "$pane" in %*[!0-9]*|'') exit 0 ;; %[0-9]*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
[ -n "$payload" ] || payload='{}'
printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1 || exit 0
if [ -z "$event" ]; then event=$(printf '%s' "$payload" | jq -r '.hook_event_name // .type // .event // empty'); fi
[ -n "$event" ] || exit 0

lock="bonsai-pane-${pane}"
tmx wait-for -L "$lock" 2>/dev/null || exit 0
trap 'tmx wait-for -U "$lock" >/dev/null 2>&1 || true' EXIT
trap 'exit 0' HUP INT TERM
previous=$(bonsai_snapshot "$pane") || exit 0
[ -n "$previous" ] || exit 0
prev=$(printf '%s' "$previous" | jq -r .state)
seq=$(printf '%s' "$previous" | jq -r .seq)
source_seq=${BONSAI_EVENT_SEQ:-$(printf '%s' "$payload" | jq -r '.bonsai_seq // .seq // 0')}
case "$source_seq" in ''|*[!0-9]*) source_seq=0 ;; esac
old_source_seq=$(printf '%s' "$previous" | jq -r .source_seq)
if [ "$source_seq" -gt 0 ] && [ "$source_seq" -le "$old_source_seq" ]; then exit 0; fi

# Read only a bounded transcript tail, and only when Stop omitted its message.
if [ "$event" = Stop ] && [ "$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')" = '' ]; then
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
  if [ -f "$transcript" ] && [ -r "$transcript" ]; then
    message=$(tail -c 65536 "$transcript" | jq -Rrc 'fromjson? | select(.type == "assistant" or .message.role == "assistant") | .message.content? // .content? | if type == "array" then map(select(.type == "text") | .text) | join(" ") elif type == "string" then . else empty end' | tail -n 1)
    [ -z "$message" ] || payload=$(printf '%s' "$payload" | jq --arg msg "$message" '.last_assistant_message=$msg')
  fi
fi
now=$(date +%s)
tools_enabled=false; [ "$(bonsai_opt @bonsai-hooks-tool-events on)" != off ] && tools_enabled=true
settle=$(bonsai_duration "$(bonsai_opt @bonsai-title-settle 3s)")
next=$(printf '%s' "$payload" | jq -c --argjson previous "$previous" --arg agent "$agent" --arg event "$event" \
  --argjson now "$now" --argjson tools "$tools_enabled" --argjson settle "${settle:-3}" -f "$BONSAI_SCRIPTS/_reduce.jq") || exit 0
if [ "$(printf '%s' "$next" | jq -r ._ignore)" = true ]; then
  if [ "$event" = Notification ]; then bonsai_log "$pane" "$event" "$prev" "$prev"; fi
  exit 0
fi
seq=$((seq + 1))
[ "$source_seq" -gt 0 ] || source_seq=$old_source_seq
next=$(printf '%s' "$next" | jq -c --argjson seq "$seq" --argjson source_seq "$source_seq" '.seq=$seq | .source_seq=$source_seq')
state=$(printf '%s' "$next" | jq -r .state)
category=$(printf '%s' "$next" | jq -r ._category)

# Keep these argv in one tmux command queue; user payload is never evaluated as
# shell code or as a tmux format. JSON compact output cannot contain raw tabs.
writes=()
while IFS=$'\t' read -r key value; do
  # tmux's argv parser treats even a quoted trailing semicolon as a command
  # separator. Escape its final semicolon for tmux as well as for the shell.
  case "$value" in *';') value="${value%;}\\;" ;; esac
  [ "${#writes[@]}" -eq 0 ] || writes+=( ';' )
  writes+=( set-option -p -t "$pane" "@agent_${key}" "$value" )
done < <(printf '%s' "$next" | jq -r 'to_entries[] | select(.key | test("^(state|state_ts|seq|type|prompt|msg|ask|tool|session|transcript|seen_ts|title_state|title_ts|hook_ts|children|child_ids|parent_done|source_seq|model|ctx)$")) | [.key, (.value | if type == "string" then . elif . == null then "" else tojson end)] | join("\t")')
tmx "${writes[@]}" 2>/dev/null || exit 0
bonsai_window_mirror "$pane"
if [ "$state" != "$prev" ] || [ -n "$category" ]; then bonsai_log "$pane" "$event" "$prev" "$state"; fi
tmx refresh-client -S 2>/dev/null || true
# Release the pane before acknowledgement/notification workers may request it.
tmx wait-for -U "$lock" 2>/dev/null || true
trap - EXIT
if [ -n "$category" ] && [ -x "$BONSAI_SCRIPTS/notify.sh" ]; then
  bonsai_detach "$BONSAI_SCRIPTS/notify.sh" deliver "$pane" "$category"
fi
if [ -x "$BONSAI_SCRIPTS/board.sh" ]; then bonsai_detach "$BONSAI_SCRIPTS/board.sh" --refresh; fi
