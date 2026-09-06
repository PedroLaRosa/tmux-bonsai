#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
opt(){ local v; v=$(tmx show-option -gqv "$1" 2>/dev/null || true); printf '%s' "${v:-$2}"; }
detect(){
  local configured; configured=$(opt @bonsai-notify-backend auto)
  [ "$configured" != auto ] && { printf '%s\n' "$configured"; return; }
  for b in terminal-notifier alerter notify-send dunstify; do command -v "$b" >/dev/null 2>&1 && { printf '%s\n' "$b"; return; }; done
  [ "$(uname -s)" = Darwin ] && { printf '%s\n' osascript; return; }
  printf '%s\n' none
}
[ "${1:-}" = backend ] && { detect; exit; }
kind=${1:-event}; pane=${2:-${TMUX_PANE:-}}; state=${3:-test}; body=${4:-'Notifications are working'}
[ "$(opt @bonsai-notify on)" = on ] || exit 0
category=$state; [ "$state" = done ] && category=finished; [ "$state" = waiting ] && category=input
[ "$(opt "@bonsai-notify-$category" on)" = on ] || exit 0
if [ "$kind" != test ] && [ "$(opt @bonsai-notify-focus strict)" != off ]; then
  active=$(tmx display-message -p '#{pane_id}' 2>/dev/null || true)
  [ "$active" = "$pane" ] && exit 0
fi
agent=$(tmx show-option -pqv -t "$pane" @agent_type 2>/dev/null || echo Agent)
title="${agent:-Agent} ${state}"
backend=$(detect); sound=$(opt "@bonsai-sound-$category" default)
case $backend in
  terminal-notifier) terminal-notifier -title "$title" -message "$body" -group "bonsai-${pane#%}" -sound "$sound" ;;
  alerter) alerter -title "$title" -message "$body" -group "bonsai-${pane#%}" -timeout 8 >/dev/null & ;;
  notify-send) notify-send -a bonsai -h "string:x-dunst-stack-tag:bonsai-${pane#%}" "$title" "$body" ;;
  dunstify) dunstify -a bonsai -r "${pane#%}" "$title" "$body" ;;
  osascript) osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$title" "$body" ;;
  command) BONSAI_CATEGORY=$category BONSAI_TITLE=$title BONSAI_BODY=$body BONSAI_PANE=$pane sh -c "$(opt @bonsai-notify-command '')" ;;
  none) exit 0 ;;
esac
