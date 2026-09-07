#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/_state.sh"
target=${1:-all}
if [ "$target" = all ]; then panes=$(tmx list-panes -a -F '#{pane_id}' 2>/dev/null); else panes=$target; fi
for pane in $panes; do
  lock="bonsai-pane-${pane}"
  tmx wait-for -L "$lock" 2>/dev/null || continue
  trap 'tmx wait-for -U "$lock" >/dev/null 2>&1 || true' EXIT
  opts=$(tmx show-options -p -t "$pane" 2>/dev/null | awk '$1 ~ /^@agent_/ { print $1 }')
  writes=()
  for opt in $opts; do
    [ "${#writes[@]}" -eq 0 ] || writes+=( ';' )
    writes+=( set-option -pu -t "$pane" "$opt" )
  done
  if [ "${#writes[@]}" -gt 0 ]; then tmx "${writes[@]}" 2>/dev/null || true; fi
  bonsai_window_mirror "$pane"
  tmx wait-for -U "$lock" 2>/dev/null || true
  trap - EXIT
done
tmx refresh-client -S 2>/dev/null || true
if [ -x "$BONSAI_SCRIPTS/board.sh" ]; then bonsai_detach "$BONSAI_SCRIPTS/board.sh" --refresh; fi
