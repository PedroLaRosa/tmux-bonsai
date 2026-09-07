#!/usr/bin/env bash
# A detached waiter keeps desktop action listeners out of the reducer path.
set -uo pipefail
source "$(dirname "$0")/_notify.sh"
backend=${1:?backend}
completed=0
finish() {
  if [ "$completed" -eq 1 ]; then decision=delivered; else decision=failed; fi
  bonsai_log "$BONSAI_PANE" notification "$BONSAI_STATE" "$BONSAI_STATE" "$BONSAI_CATEGORY" "$decision" "$backend" "$BONSAI_ID"
  bonsai_notify_health "$backend" "$decision"
}
trap finish EXIT
case "$backend" in
  alerter)
    args=(-title "$BONSAI_TITLE" -message "$BONSAI_BODY" -group "$BONSAI_ID" -actions Jump -timeout 30 -json)
    [ -z "$BONSAI_SOUND" ] || args+=(-sound "$BONSAI_SOUND")
    result=$(alerter "${args[@]}") || exit 1
    completed=1
    if printf '%s' "$result" | jq -e '.activationValue=="Jump" or .activationType=="contentsClicked"' >/dev/null 2>&1; then
      "$BONSAI_SCRIPTS/bonsai" -S "$BONSAI_SOCKET" jump "$BONSAI_PANE"
    fi;;
  notify-send|dunstify)
    id=$(bonsai_notify_id "$BONSAI_PANE" "$backend")
    args=(-a bonsai -p -r "$id" -h "string:x-dunst-stack-tag:$BONSAI_ID" -h "string:sound-name:$BONSAI_SOUND")
    if [ "$backend" = notify-send ]; then args+=(-A jump=Jump --wait); else args+=(-A 'jump,Jump'); fi
    "$backend" "${args[@]}" "$BONSAI_TITLE" "$BONSAI_BODY" | while IFS= read -r value; do
      if [[ "$value" =~ ^[0-9]+$ ]]; then bonsai_store_notify_id "$BONSAI_PANE" "$backend" "$value"
      elif [ "$value" = jump ]; then "$BONSAI_SCRIPTS/bonsai" -S "$BONSAI_SOCKET" jump "$BONSAI_PANE"; fi
    done
    [ "${PIPESTATUS[0]}" -ne 0 ] || completed=1;;
esac
