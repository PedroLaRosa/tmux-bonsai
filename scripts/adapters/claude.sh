#!/usr/bin/env bash
agent=claude; cli=claude; shape=claude
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
events='SessionStart UserPromptSubmit PermissionRequest Notification Stop StopFailure SubagentStart SubagentStop PostCompact SessionEnd'
[ "$tools_mode" = off ] || events="$events PreToolUse PostToolUse PostToolUseFailure"
if [ "$action" = explain ]; then
    adapter_record installed 'Observe-only lifecycle hooks. Optional usage: bonsai hooks install claude-statusline. Claude terminal bell remains your choice in preferredNotifChannel.'
    printf '%s\n' 'https://code.claude.com/docs/en/hooks'
    exit 0
fi
adapter_check
adapter_json
