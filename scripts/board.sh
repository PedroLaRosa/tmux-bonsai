#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v fzf >/dev/null || { echo 'bonsai board requires fzf' >&2; exit 1; }
while :; do
  row=$($S/agent-list.sh | fzf --ansi --no-sort --prompt='agents> ' --header='enter jump · ctrl-r refresh' --bind='ctrl-r:reload('"$S"'/agent-list.sh)') || exit 0
  pane=$(printf '%s\n' "$row" | sed -n 's/.*:\([0-9][0-9]*\)\.\(%[0-9][0-9]*\).*/\2/p')
  [ -n "$pane" ] && exec "$S/jump.sh" "$pane"
done
