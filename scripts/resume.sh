#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane=${1:-}; [ -n "$pane" ] || { echo 'usage: bonsai resume PANE [--yes]' >&2; exit 2; }
yes=off; [ "${2:-}" != --yes ] || yes=on
record=$("$BONSAI_SCRIPTS/list.sh" --json | jq -cer --arg pane "$pane" '.[]|select(.pane_id==$pane)') || exit 1
state=$(printf '%s' "$record" | jq -r .state)
[ "$state" = exited ] || { echo 'Resume requires an exited agent.' >&2; exit 1; }
agent=$(printf '%s' "$record" | jq -r .agent)
session=$(printf '%s' "$record" | jq -r .agent_session)
[ -n "$session" ] || { echo 'No agent session ID was recorded.' >&2; exit 1; }
case "$agent" in claude) command=(claude --resume "$session");; opencode) command=(opencode --session "$session");; codex) command=(codex resume "$session");;
 *) echo "Resume is not supported for $agent." >&2; exit 1;; esac
command -v "${command[0]}" >/dev/null || { echo "$agent is not installed" >&2; exit 1; }
printf -v launch '%q ' "${command[@]}"
if [ "$yes" = on ]; then exec "$BONSAI_SCRIPTS/reply.sh" "$pane" --yes -- "$launch"
else exec "$BONSAI_SCRIPTS/reply.sh" "$pane" -- "$launch"; fi
