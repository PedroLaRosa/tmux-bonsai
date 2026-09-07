#!/usr/bin/env bash
agent=codex; cli=codex; shape=claude
config=${CODEX_HOME:-$HOME/.codex}/hooks.json
# shellcheck source=_common.sh
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
events='SessionStart SessionEnd UserPromptSubmit PermissionRequest Stop Interrupt SubagentStart SubagentStop PostCompact'
[ "$tools_mode" = off ] || events="$events PreToolUse PostToolUse"
installed_detail='configured; review and trust these exact definitions in Codex /hooks; trust/runtime enablement is not verified'
if [ "$action" = explain ]; then
    adapter_record partial "$installed_detail"
    printf '%s\n' 'Current Codex enables hooks by default; features.hooks=false or managed policy may disable them. Bonsai never writes trust hashes, changes policy, or bypasses trust. Keep the notify adapter for older versions.' 'https://learn.chatgpt.com/docs/hooks'
    exit 0
fi
adapter_check
adapter_json
