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
previous=''; [ ! -f "$cursor" ] || IFS='' read -r previous < "$cursor"
target=$(printf '%s\n' "$candidates" | awk -v previous="$previous" 'NR==1 {first=$0} found {print; exit} $0==previous {found=1} END {if(!found || $0==previous) print first}')
# On the last row, wrap exactly once.
target=${target%%$'\n'*}
printf '%s\n' "$target" > "$cursor"
exec "$BONSAI_SCRIPTS/jump.sh" "$target"
