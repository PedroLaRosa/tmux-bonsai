#!/usr/bin/env bash
# Sourced by the tiny provider entry points. Never parse JSON in the foreground.
# The entry point supplies bonsai_agent before sourcing this library.
# shellcheck disable=SC2154
case "${TMUX_PANE:-}" in %*) ;; *) exit 0 ;; esac
[ "$bonsai_agent" != claude ] || [ -z "${CLAUDE_JOB_DIR:-}" ] || exit 0
if [ "${bonsai_payload_set:-}" != 1 ]; then
    IFS= read -r -d '' bonsai_payload || :
fi
# Capture source order before detaching; the reducer still works without Perl.
if [ -z "${BONSAI_EVENT_SEQ:-}" ]; then
    if [ -n "${EPOCHREALTIME:-}" ]; then
        BONSAI_EVENT_SEQ=${EPOCHREALTIME/./}
    elif command -v perl >/dev/null 2>&1; then
        BONSAI_EVENT_SEQ=$(perl -e 'require Time::HiRes; printf "%.0f", Time::HiRes::time()*1000000' 2>/dev/null)
    fi
    export BONSAI_EVENT_SEQ
fi
(
    trap '' HUP
    # Create the payload pipe only after closing ALL inherited agent pipe ends.
    # Payload stays in shell memory: no argv size limit or temporary prompt file.
    if command -v setsid >/dev/null 2>&1; then
        printf '%s' "$bonsai_payload" | setsid "${BASH_SOURCE[0]%/hooks/_dispatch.sh}/agent-event.sh" "$bonsai_agent" "${bonsai_event:-}"
    else
        printf '%s' "$bonsai_payload" | nohup "${BASH_SOURCE[0]%/hooks/_dispatch.sh}/agent-event.sh" "$bonsai_agent" "${bonsai_event:-}"
    fi
) </dev/null >/dev/null 2>&1 &
exit 0
