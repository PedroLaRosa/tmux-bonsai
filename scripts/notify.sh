#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/_notify.sh"
mode=${1:-status}; shift || true
case "$mode" in
  dismiss) bonsai_dismiss "${1:?pane}"; exit;;
  test) exec "$BONSAI_SCRIPTS/notify-test.sh" "$@";;
  status)
    backend=$(bonsai_backends)
    printf 'notifications: %s\nbackend: %s\nfocus: %s\n' "$(bonsai_opt @bonsai-notify on)" "$backend" "$(bonsai_opt @bonsai-notify-focus strict)"
    evidence="$(bonsai_state_dir)/notify-verify"
    if [ -f "$evidence" ]; then cat "$evidence"; else echo 'verification: never tested'; fi
    exit;;
  bell) pane=${1:-${TMUX_PANE:-}}; category=bell; shift || true;;
  deliver) pane=${1:?pane required}; category=${2:?category required}; shift 2;;
  remind)
    pane=${1:?pane}; token=${2:?generation}; delay=${3:?delay}; sleep "$delay"
    [ "$(bonsai_pane_opt "$pane" @agent_reminder_token)" = "$token" ] || exit 0
    snapshot=$(bonsai_snapshot "$pane") || exit 0
    printf '%s' "$snapshot" | jq -e --argjson token "$token" '(if (.generation // 0)>0 then .generation else .seq end)==$token and .state=="waiting" and .seen_ts<.state_ts' >/dev/null || exit 0
    exec "$0" deliver "$pane" input --reminder --generation "$token";;
  *) echo 'Usage: bonsai notify test|status|deliver PANE CATEGORY' >&2; exit 2;;
esac
[ -n "$pane" ] || exit 0
case "$category" in finished|input|error|bell|test) ;; *) echo 'Invalid category' >&2; exit 2;; esac
test_mode=0; reminder=0; expected_seq=''; expected_generation=''
while [ $# -gt 0 ]; do
  case "$1" in --test) test_mode=1;; --reminder) reminder=1;; --seq) expected_seq=${2:?sequence required}; shift;; --generation) expected_generation=${2:?generation required}; shift;; esac
  shift
done
snapshot=$(bonsai_snapshot "$pane") || exit 0
[ -n "$snapshot" ] || exit 0
state=$(printf '%s' "$snapshot" | jq -r .state)
token=$(printf '%s' "$snapshot" | jq -r 'if (.generation // 0)>0 then .generation else .seq end')
current_generation() {
  local generation
  generation=$(bonsai_pane_opt "$pane" @agent_generation 0) || return 1
  if [ "$generation" -gt 0 ]; then printf '%s' "$generation"; else bonsai_pane_opt "$pane" @agent_seq -1; fi
}
log_decision() { bonsai_log "$pane" notification "$state" "$state" "$category" "$1" "${2:-}" "bonsai-$pane"; }
if [ "$test_mode" -eq 0 ]; then
  if { [ -n "$expected_seq" ] && [ "$expected_seq" != "$(printf '%s' "$snapshot" | jq -r .seq)" ]; } || { [ -n "$expected_generation" ] && [ "$expected_generation" != "$token" ]; }; then log_decision grace-cancelled; exit 0; fi
  case "$category:$state" in
    finished:done|finished:stopped|input:waiting|error:error|bell:*|test:*) ;;
    *) log_decision grace-cancelled; exit 0;;
  esac
  [ "$(bonsai_opt @bonsai-notify on)" = on ] || { log_decision disabled; exit 0; }
  toggle="@bonsai-notify-$category"; fallback=on
  if [ "$category" = bell ]; then toggle=@bonsai-notify-on-bell; fallback=off; fi
  [ "$(bonsai_opt "$toggle" "$fallback")" = on ] || { log_decision category-off; exit 0; }
  if bonsai_is_focused "$pane" "$(bonsai_opt @bonsai-notify-focus strict)"; then
    "$BONSAI_SCRIPTS/ack.sh" "$pane"
    log_decision suppressed-focus; exit 0
  fi
  now=$(date +%s); cooldown=$(bonsai_duration "$(bonsai_opt @bonsai-notify-cooldown 5)")
  last=$(printf '%s' "$snapshot" | jq -r .notified_ts)
  hook_ts=$(printf '%s' "$snapshot" | jq -r .hook_ts)
  if awk -v n="$now" -v last="$last" -v hook="$hook_ts" -v cd="$cooldown" -v cat="$category" 'BEGIN {exit !((last>0 && n-last<cd) || (cat=="bell" && hook>0 && n-hook<cd))}'; then
    log_decision cooldown; exit 0
  fi
  grace=0
  [ "$category" != finished ] || grace=$(bonsai_duration "$(bonsai_opt @bonsai-notify-grace 1.5)")
  agent=$(printf '%s' "$snapshot" | jq -r .type)
  [ "$category:$agent" != input:codex ] || grace=0.5
  if [ "$grace" != 0 ]; then
    sleep "$grace"
    current=$(current_generation) || exit 0
    if [ "$current" != "$token" ]; then log_decision grace-cancelled; exit 0; fi
  fi
fi
# Reserve delivery under a short lock after grace; simultaneous decisions cannot
# both consume the same cooldown or replace a newer generation's banner.
tmx wait-for -L "bonsai-notify-$pane" || exit 1
trap 'tmx wait-for -U "bonsai-notify-$pane" 2>/dev/null || true' EXIT
if [ "$test_mode" -eq 0 ]; then
  current=$(current_generation) || exit 0
  if [ "$current" != "$token" ]; then log_decision grace-cancelled; exit 0; fi
  if bonsai_is_focused "$pane" "$(bonsai_opt @bonsai-notify-focus strict)"; then
    "$BONSAI_SCRIPTS/ack.sh" "$pane"; log_decision suppressed-focus; exit 0
  fi
  if [ "$reminder" -eq 1 ]; then
    [ "$(bonsai_pane_opt "$pane" @agent_reminder_token)" = "$token" ] || exit 0
    tmx set -p -t "$pane" @agent_reminder_token ''
  fi
  last=$(bonsai_pane_opt "$pane" @agent_notified_ts 0)
  if awk -v n="$(date +%s)" -v last="$last" -v cd="$cooldown" 'BEGIN {exit !(last>0 && n-last<cd)}'; then log_decision cooldown; exit 0; fi
fi
export BONSAI_PANE=$pane BONSAI_CATEGORY=$category BONSAI_STATE=$state BONSAI_ID="bonsai-$pane"
export BONSAI_SOCKET="${BONSAI_SOCKET:-${TMUX:-}}"; BONSAI_SOCKET=${BONSAI_SOCKET%%,*}
BONSAI_SESSION=$(printf '%s' "$snapshot" | jq -r .session_name)
BONSAI_WINDOW_NAME=$(printf '%s' "$snapshot" | jq -r .window_name)
BONSAI_CWD=$(printf '%s' "$snapshot" | jq -r .cwd)
BONSAI_AGENT=$(printf '%s' "$snapshot" | jq -r '.type | if .=="" then "agent" else . end')
BONSAI_WINDOW=$(tmx display -p -t "$pane" '#{window_index}')
BONSAI_BRANCH=$(git -C "$BONSAI_CWD" symbolic-ref --short HEAD 2>/dev/null) || BONSAI_BRANCH=$BONSAI_WINDOW_NAME
repo_path=$(git -C "$BONSAI_CWD" rev-parse --show-toplevel 2>/dev/null) || repo_path=$BONSAI_CWD
BONSAI_REPO=${repo_path##*/}
location=$(tmx display -p -t "$pane" '#{session_name}:#{window_index}.#{pane_index}')
case "$category" in finished) suffix=finished; [ "$state" != stopped ] || suffix=stopped;; input) suffix='needs input';; error) suffix=failed;; bell) suffix='terminal bell';; test) suffix='notifications are on';; esac
BONSAI_TITLE="$BONSAI_BRANCH · $BONSAI_AGENT $suffix"
[ "$reminder" -eq 0 ] || BONSAI_TITLE="$BONSAI_TITLE · still waiting"
BONSAI_BODY=$(printf '%s' "$snapshot" | jq -r --arg cat "$category" --arg location "$location" '
  if $cat=="input" and .ask!="" then .ask elif .msg!="" then .msg elif .tool!="" then "Using "+.tool elif .prompt!="" then "Prompt: "+.prompt else $location end | .[:180]')
[ "$(bonsai_opt @bonsai-notify-preview on)" = on ] || BONSAI_BODY=$location
if [ "$test_mode" -eq 1 ]; then BONSAI_TITLE='bonsai notifications are on'; BONSAI_BODY='Click to jump back to this pane'; fi
BONSAI_SUBTITLE=$location
# Window/repository names are user data too; OSC cannot contain control bytes.
BONSAI_TITLE=$(printf '%s' "$BONSAI_TITLE" | jq -Rs 'gsub("[\u0000-\u001f\u007f-\u009f]"; " ") | .[:240]' -r)
BONSAI_BODY=$(printf '%s' "$BONSAI_BODY" | jq -Rs 'gsub("[\u0000-\u001f\u007f-\u009f]"; " ") | .[:180]' -r)
BONSAI_SUBTITLE=$(printf '%s' "$BONSAI_SUBTITLE" | jq -Rs 'gsub("[\u0000-\u001f\u007f-\u009f]"; " ")' -r)
BONSAI_JUMP_CMD="$(bonsai_shell_quote "$BONSAI_SCRIPTS/bonsai") -S $(bonsai_shell_quote "$BONSAI_SOCKET") jump $(bonsai_shell_quote "$pane")"
sound_mode=$(bonsai_opt @bonsai-sound-mode system)
BONSAI_SOUND=''
case "$sound_mode" in system|both) BONSAI_SOUND=$(bonsai_opt "@bonsai-sound-$category");; esac
[ "$state" != stopped ] || BONSAI_SOUND=''
export BONSAI_TITLE BONSAI_BODY BONSAI_SUBTITLE BONSAI_SESSION BONSAI_WINDOW BONSAI_WINDOW_NAME BONSAI_AGENT BONSAI_BRANCH BONSAI_REPO BONSAI_CWD BONSAI_SOUND BONSAI_JUMP_CMD
backends=$(bonsai_backends); delivered=0
IFS=',' read -r -a backend_list <<< "$backends"
for backend in "${backend_list[@]}"; do
  if ! bonsai_backend_available "$backend"; then log_decision backend-missing "$backend"; continue; fi
  bonsai_deliver_backend "$backend" >/dev/null 2>&1
  result=$?
  case "$result" in
    0) delivered=1; log_decision delivered "$backend"; bonsai_notify_health "$backend" delivered;;
    3) delivered=1; log_decision queued "$backend";;
    *) log_decision failed "$backend"; bonsai_notify_health "$backend" failed;;
  esac
done
if [ "$delivered" -eq 1 ]; then
  tmx set -p -t "$pane" @agent_notified_ts "$(date +%s)" \; set -p -t "$pane" @agent_notify_id "$BONSAI_ID" \; set -p -t "$pane" @agent_notify_backends "$backends" 2>/dev/null || true
  bonsai_play_sound "$sound_mode" "$BONSAI_SOUND" "$backends"
fi
tmx wait-for -U "bonsai-notify-$pane"; trap - EXIT
if [ "$delivered" -eq 1 ] && [ "$category" = input ] && [ "$test_mode" -eq 0 ] && [ "$reminder" -eq 0 ]; then
  remind=$(bonsai_opt @bonsai-notify-remind 10m)
  if [ "$remind" != off ]; then
    # Acknowledgement clears this token even if the pane is marked unread again.
    tmx wait-for -L "bonsai-pane-$pane"
    seen=$(bonsai_pane_opt "$pane" @agent_seen_ts 0)
    state_ts=$(bonsai_pane_opt "$pane" @agent_state_ts 0)
    current=$(current_generation)
    schedule=0
    if [ "$seen" -lt "$state_ts" ] && [ "$current" = "$token" ]; then
      tmx set -p -t "$pane" @agent_reminder_token "$token"
      schedule=1
    fi
    tmx wait-for -U "bonsai-pane-$pane"
    if [ "$schedule" -eq 1 ]; then delay=$(bonsai_duration "$remind") && bonsai_detach "$0" remind "$pane" "$token" "$delay"; fi
  fi
fi
[ "$delivered" -eq 1 ]
