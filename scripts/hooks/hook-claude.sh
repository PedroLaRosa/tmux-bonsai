#!/usr/bin/env bash
# Claude invokes hooks synchronously. Capture stdin and detach the reducer so
# notification delivery can never delay the agent.
set -u
S=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
event=${1:-Unknown}; payload=$(cat)
( "$S/agent-event.sh" claude "$event" "$payload" </dev/null >/dev/null 2>&1 ) &
exit 0
