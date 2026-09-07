#!/usr/bin/env bash
bonsai_agent=copilot
bonsai_event=${1:-}
# shellcheck source=_dispatch.sh
. "${BASH_SOURCE[0]%/*}/_dispatch.sh"
