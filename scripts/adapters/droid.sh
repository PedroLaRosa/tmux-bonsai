#!/usr/bin/env bash
agent=droid; cli=droid; shape=droid
config=$HOME/.factory/hooks.json
# shellcheck source=_common.sh
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
events='SessionStart SessionEnd UserPromptSubmit Stop SubagentStop Notification'
[ "$tools_mode" = off ] || events="$events PreToolUse PostToolUse"
if [ "$action" = explain ]; then
    adapter_record installed 'Factory user hooks.json takes precedence over settings.json hooks. Permission waits use Notification; PermissionRequest is not documented by Factory.'
    printf '%s\n' 'https://docs.factory.ai/harness/hooks'
    exit 0
fi
adapter_check
# Creating hooks.json would hide a user's legacy settings.json hooks. Migrate
# their complete hooks block into the new file before adding our handlers.
if [ "$action" = install ] && [ ! -f "$config" ] && [ -z "${BONSAI_ADAPTER_CONFIG:-}" ] && [ -f "$HOME/.factory/settings.json" ]; then
    adapter_json_input() { jq '{hooks: (.hooks // {})}' "$HOME/.factory/settings.json"; }
fi
adapter_json
