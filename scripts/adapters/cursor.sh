#!/usr/bin/env bash
agent=cursor; cli=agent; shape=cursor
command -v cursor-agent >/dev/null 2>&1 && cli=cursor-agent
config=$HOME/.cursor/hooks.json
# shellcheck source=_common.sh
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
events='beforeSubmitPrompt stop afterAgentResponse'
[ "$tools_mode" = off ] || events="$events preToolUse postToolUse postToolUseFailure beforeShellExecution beforeMCPExecution"
if [ "$action" = explain ]; then
    adapter_record installed 'Neutral JSON responses observe progress and preserve Cursor permission decisions. CLI versions may support fewer hook events.'
    printf '%s\n' 'https://cursor.com/docs/hooks'
    exit 0
fi
adapter_check
adapter_json
