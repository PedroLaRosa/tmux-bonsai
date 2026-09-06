#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
pane=$(tmx list-panes -a -F '#{@agent_state_ts}\t#{pane_id}\t#{@agent_state}' | awk -F '\t' '$3=="waiting" {print}' | sort -n | awk -F '\t' 'NR==1{print $2}')
[ -n "$pane" ] || { tmx display-message 'bonsai: no agent needs you'; exit 1; }
exec "$S/jump.sh" "$pane"
