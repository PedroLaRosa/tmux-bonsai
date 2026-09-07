#!/usr/bin/env bash
agent=copilot; cli=copilot; shape=copilot
config=${COPILOT_HOME:-$HOME/.copilot}/hooks/tmux-bonsai.json
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
events='SessionStart SessionEnd UserPromptSubmit PermissionRequest Stop ErrorOccurred SubagentStart SubagentStop'
[ "$tools_mode" = off ] || events="$events PreToolUse PostToolUse PostToolUseFailure"
if [ "$action" = explain ]; then
    adapter_record installed 'Current Copilot CLI loads user hooks/*.json. PascalCase events select snake_case payloads. Older CLIs may require an upgrade for global hooks.'
    printf '%s\n' 'https://docs.github.com/en/copilot/reference/hooks-reference'
    exit 0
fi
adapter_check
adapter_json
