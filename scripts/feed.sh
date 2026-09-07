#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
log="$(bonsai_state_dir)/events.jsonl"
mode=interactive tail_mode=off why=off
for arg in "$@"; do
 case "$arg" in --json) mode=json;; --rows) mode=rows;; --tail) tail_mode=on;; --why) why=on;; *) echo "unknown feed option: $arg" >&2; exit 2;; esac
done
[ -f "$log" ] || { [ "$mode" != json ] || printf '[]\n'; exit 0; }
# Current log records nest notification outcomes under notify. Retain support
# for earlier flat records while keeping every feed mode on the same filter.
BONSAI_GLYPHS=$(bonsai_opt @bonsai-glyphs unicode)
export BONSAI_GLYPHS
glyphs=$(for state in waiting working 'done' idle error stopped exited unknown; do printf '%s\037' "$state"; bonsai_glyph "$state"; printf '\n'; done)
filter='
 def decision: .notify.decision // .decision // "state";
 def backend: .notify.backend // .backend // "";
 def keep: $why!="on" or decision!="delivered";
 def glyph: .state as $state | ($glyphs|split("\n")|map(split("\u001f")|{key:.[0],value:.[1]})|from_entries)[$state]//"?";
 def summary: if .state=="waiting" and (.ask//"")!="" then .ask
  elif (.summary//"")!="" then .summary else .event//"" end;
 def render: (.ts|todateiso8601)+"  "+(glyph)+" "+(.agent//"")+" "+(.branch//"")+" "+(.state//"")+" · "+
  summary+" · "+decision+(if backend!="" then " ("+backend+")" else "" end);
 def output: if $mode=="json" then . elif $mode=="rows" then [(.pane//""),render]|join("\u001f") else render end;
'
if [ "$tail_mode" = on ]; then
 tail -n 30 -F "$log" | jq --unbuffered -Rrc --arg mode "$mode" --arg why "$why" --arg glyphs "$glyphs" \
  "$filter fromjson? | select(keep) | output"
 exit
fi
if [ "$mode" = json ]; then
 jq -s --arg mode "$mode" --arg why "$why" --arg glyphs "$glyphs" "$filter map(select(keep))|reverse" "$log"; exit
fi
if [ "$mode" = rows ]; then
 jq -sr --arg mode "$mode" --arg why "$why" --arg glyphs "$glyphs" "$filter reverse[]|select(keep)|output" "$log"; exit
fi
self=$(printf '%q' "$BONSAI_SCRIPTS/feed.sh")
selected=$("$BONSAI_SCRIPTS/feed.sh" --rows | fzf --delimiter $'\037' --with-nth 2 --layout reverse --no-sort \
 --header 'enter jump · ctrl-w why not notified · ctrl-a all · esc back' \
 --bind "ctrl-w:reload($self --rows --why),ctrl-a:reload($self --rows)") || wt_back
[ -z "$selected" ] || "$BONSAI_SCRIPTS/jump.sh" "${selected%%$'\037'*}"
