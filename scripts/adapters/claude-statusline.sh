#!/usr/bin/env bash
agent=claude-statusline; cli=claude; shape=claude
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
if [ "$action" = explain ]; then
    adapter_record installed 'Optional, silent usage adapter fills model/context pane fields. Existing statusLine commands are preserved; invoke hook-claude-statusline.sh from your own script to compose it.'
    printf '%s\n' 'https://code.claude.com/docs/en/statusline'
    exit 0
fi
adapter_check
printf -v quoted '%q' "$ADAPTER_SCRIPTS/hooks/hook-claude-statusline.sh"
desired="$quoted # tmux-bonsai:claude-statusline"
adapter_json_input | jq -e 'type == "object"' >/dev/null 2>&1 || adapter_error 'invalid JSON config; left unchanged'
current=$(adapter_json_input | jq -r '.statusLine.command // ""')
owned=0
case "$current" in *' # tmux-bonsai:claude-statusline') owned=1 ;; esac
case "$action" in
    status)
        if [ "$current" = "$desired" ]; then adapter_record installed 'model/context usage adapter configured'
        elif [ "$owned" = 1 ]; then adapter_record partial 'plugin path drift; run install to repair'
        else adapter_record not_installed 'optional usage adapter not configured'; fi
        ;;
    install|remove)
        if [ "$action" = install ] && [ "$owned" = 0 ] && adapter_json_input | jq -e 'has("statusLine") and .statusLine != null' >/dev/null; then adapter_error 'existing statusLine preserved; compose this hook in your script'; fi
        [ "$action" != remove ] || [ "$owned" = 1 ] || { adapter_record not_installed 'no managed statusLine'; exit 0; }
        adapter_lock
        adapter_json_input | jq --arg command "$desired" --arg action "$action" 'if $action == "install" then .statusLine = {type: "command", command: $command} else del(.statusLine) end' > "$temp"
        adapter_replace
        if [ "$action" = install ]; then adapter_record installed 'silent usage adapter configured'
        else adapter_record not_installed 'managed statusLine removed'; fi
        ;;
esac
