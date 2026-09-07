#!/usr/bin/env bash
bonsai_agent=cursor
bonsai_event=${1:-}
# Observe only. Empty decisions preserve Cursor's normal permission handling.
case "$bonsai_event" in
    beforeSubmitPrompt) printf '{"continue":true}\n' ;;
    *) printf '{}\n' ;;
esac
# shellcheck source=_dispatch.sh
. "${BASH_SOURCE[0]%/*}/_dispatch.sh"
