#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
# Status needs only pane options: do not pay for process or git discovery here.
counts=$(tmx list-panes -a -F '#{@agent_type} #{@agent_state} #{@agent_state_ts} #{@agent_seen_ts}' 2>/dev/null | awk '
 $2=="waiting" {waiting++} $2=="error" {error++} $2=="working" {working++}
 $2=="done" && $3+0>$4+0 {done++}
 END {printf "%d %d %d %d",waiting,error,working,done}')
read -r waiting error working completed <<< "$counts"
out=''
for item in "waiting:$waiting:colour214" "error:$error:colour196" "working:$working:colour39" "done:$completed:colour78"; do
 state=${item%%:*}; rest=${item#*:}; count=${rest%%:*}; colour=${rest#*:}
 [ "${count:-0}" -gt 0 ] || continue
 out="$out#[fg=$colour]$(bonsai_glyph "$state")$count "
done
if [ "$(bonsai_opt @bonsai-notify on)" = on ]; then
 verify="$(bonsai_state_dir)/notify-verify"
 if [ ! -f "$verify" ] || ! grep -Eq '(^|[[:space:]])(delivered|displayed|verified)([[:space:]]|$)|"outcome"[[:space:]]*:[[:space:]]*"(delivered|displayed|verified)"' "$verify"; then
  glyph='!'; [ "$(bonsai_opt @bonsai-glyphs unicode)" != emoji ] || glyph='🔕'
  out="$out#[fg=colour214]$glyph "
 fi
fi
[ -z "$out" ] || printf '#[range=user|bonsai]%s#[default]#[norange]' "$out"
