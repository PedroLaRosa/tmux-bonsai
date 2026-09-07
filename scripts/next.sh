#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
json=$("$BONSAI_SCRIPTS/list.sh" --json --sort state) || exit 1
candidates=$(printf '%s' "$json" | jq -r '.[]|select(.state=="waiting" or .state=="error" or (.state=="done" and .unseen))|.pane_id')
if [ -z "$candidates" ]; then
 working=$(printf '%s' "$json" | jq '[.[]|select(.state=="working")]|length')
 tmx display-message "bonsai: nothing needs you · $working working"; exit 0
fi
cursor="$(bonsai_state_dir)/next-cursor-$(bonsai_server_key)"
pending=''; [ ! -f "$cursor" ] || IFS='' read -r pending < "$cursor"
# Remember the successor before jumping: acknowledgement removes a done row
# from the next snapshot and must not send the cycle back to its first row.
read -r target successor <<< "$(printf '%s\n' "$candidates" | awk -v pending="$pending" '
 {rows[++n]=$0; if($0==pending) wanted=n}
 END {i=wanted?wanted:1; print rows[i],rows[i%n+1]}')"
printf '%s\n' "$successor" > "$cursor"
exec "$BONSAI_SCRIPTS/jump.sh" "$target"
