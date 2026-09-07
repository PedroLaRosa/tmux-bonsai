#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"
event=${1:-}; pane=${2:-}; tty=${3:-}; window=${4:-}
case "$event" in
  ack)
    # Selection hooks may fire without a client or for a background window.
    active=$(tmx list-clients -F $'#{client_tty}\t#{pane_id}' 2>/dev/null | awk -F '\t' -v tty="$tty" '$1==tty {print $2; exit}')
    [ -z "$active" ] || exec "$BONSAI_SCRIPTS/ack.sh" "$active";;
  focus-in)
    "$BONSAI_SCRIPTS/focus.sh" in "$tty"
    exec "$0" ack "$pane" "$tty";;
  focus-out|detach) exec "$BONSAI_SCRIPTS/focus.sh" out "$tty";;
  title) exec "$BONSAI_SCRIPTS/title.sh" "$pane";;
  bell) exec "$BONSAI_SCRIPTS/notify.sh" bell "$pane";;
  silence) printf '{"state":"done"}' | "$BONSAI_SCRIPTS/agent-event.sh" manual mark --pane "$pane";;
  exit)
    source "$BONSAI_SCRIPTS/_state.sh"
    [ -z "$window" ] || bonsai_window_mirror "$window"
    "$BONSAI_SCRIPTS/board.sh" --refresh;;
esac
