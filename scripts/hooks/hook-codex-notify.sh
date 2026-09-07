#!/usr/bin/env bash
bonsai_agent=codex
bonsai_payload=${1:-}
bonsai_payload_set=1
bonsai_event=agent-turn-complete
# shellcheck source=_dispatch.sh
. "${BASH_SOURCE[0]%/*}/_dispatch.sh"
