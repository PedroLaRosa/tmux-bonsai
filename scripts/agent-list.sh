#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
mode=${1:-rows}; [ "$mode" = --json ] && mode=json; [ "$mode" = --counts ] && mode=counts
format='#{pane_id}\t#{session_name}\t#{window_index}\t#{window_name}\t#{pane_current_path}\t#{@agent_state}\t#{@agent_state_ts}\t#{@agent_type}\t#{@agent_msg}\t#{@agent_unread}'
data=$(tmx list-panes -a -F "$format" | awk -F '\t' '$6 != ""')
case $mode in
  counts) printf '%s\n' "$data" | awk -F '\t' '{n[$6]++} END {printf "waiting=%d working=%d done=%d error=%d total=%d\n",n["waiting"],n["working"],n["done"],n["error"],NR}' ;;
  json) command -v jq >/dev/null || { echo 'jq is required for --json' >&2; exit 1; }
    printf '%s\n' "$data" | jq -Rsc 'split("\n") | map(select(length>0)|split("\t")|{pane:.[0],session:.[1],window:(.[2]|tonumber),window_name:.[3],cwd:.[4],state:.[5],updated_at:(.[6]|tonumber),agent:.[7],message:.[8],unread:(.[9]=="1")})' ;;
  *) printf '%s\n' "$data" | awk -F '\t' '{glyph=($6=="waiting"?"●":$6=="working"?"◐":$6=="done"?"✔":$6=="error"?"!":"·"); printf "%s  %-9s %-18s %s:%s.%s  %s\n",glyph,$6,$8,$2,$3,$1,$9}' ;;
esac
