#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
log="$(bonsai_state_dir)/events.jsonl"
mode=interactive tail_mode=off why=off
for arg in "$@"; do
 case "$arg" in --json) mode=json;; --rows) mode=rows;; --tail) tail_mode=on;; --why) why=on;; *) echo "unknown feed option: $arg" >&2; exit 2;; esac
done
[ -f "$log" ] || { [ "$mode" != json ] || printf '[]\n'; exit 0; }
if [ "$tail_mode" = on ]; then
 if [ "$mode" = json ]; then exec tail -n 30 -F "$log"; fi
 tail -n 30 -F "$log" | jq --unbuffered -Rr 'fromjson? | "\(.ts|todateiso8601) \(.pane) \(.state) · \(.summary // .event // "") · \(.decision // "state") \(.backend // "")"'; exit
fi
if [ "$mode" = json ]; then jq -s --arg why "$why" 'map(select($why!="on" or .decision!="delivered"))|reverse' "$log"; exit; fi
if [ "$mode" = rows ]; then
 jq -sr --arg why "$why" 'reverse[]|select($why!="on" or (.decision!="delivered" and .decision!="accepted"))|
 [(.pane//""), ((.ts|todateiso8601)+"  "+(.agent//"")+" "+(.state//"")+" · "+(.summary//.event//"")+" · "+(.decision//"state")+" "+(.backend//""))]|join("\u001f")' "$log"; exit
fi
self=$(printf '%q' "$BONSAI_SCRIPTS/feed.sh")
selected=$("$BONSAI_SCRIPTS/feed.sh" --rows | fzf --delimiter $'\037' --with-nth 2 --layout reverse --no-sort \
 --header 'enter jump · ctrl-w why not notified · ctrl-a all · esc back' \
 --bind "ctrl-w:reload($self --rows --why),ctrl-a:reload($self --rows)") || wt_back
[ -z "$selected" ] || "$BONSAI_SCRIPTS/jump.sh" "${selected%%$'\037'*}"
