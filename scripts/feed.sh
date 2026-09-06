#!/usr/bin/env bash
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
file="$(bonsai_state_dir)/events.jsonl"
[ -f "$file" ] || { echo 'No agent events yet.'; exit; }
if command -v jq >/dev/null; then tail -n 200 "$file" | jq -r '(.ts|todateiso8601)+"  "+.pane+"  "+.previous+" → "+.state+"  "+.summary+"  ["+.decision+"]"'; else tail -n 200 "$file"; fi
