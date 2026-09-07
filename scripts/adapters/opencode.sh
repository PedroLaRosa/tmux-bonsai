#!/usr/bin/env bash
agent=opencode; cli=opencode; shape=plugin
config=${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/tmux-bonsai.js
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
if [ "$action" = explain ]; then
    adapter_record installed 'Directory plugin API: named async factory, root-session attribution, child waits, throttled previews. Runtime hook/plugin availability depends on your OpenCode version.'
    printf '%s\n' 'https://opencode.ai/docs/plugins/'
    exit 0
fi
adapter_check
managed=0
if [ -f "$config" ]; then
    IFS= read -r first < "$config" || :
    [ "$first" != '// tmux-bonsai managed opencode plugin v1' ] || managed=1
fi
generate_plugin() {
    local path tool_flag
    path=$(jq -Rn --arg path "$ADAPTER_SCRIPTS/hooks/hook-opencode.sh" '$path')
    tool_flag=false; [ "$tools_mode" != on ] || tool_flag=true
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            'const hook = __BONSAI_HOOK_PATH__;') printf 'const hook = %s;\n' "$path" ;;
            'const toolEvents = __BONSAI_TOOL_EVENTS__;') printf 'const toolEvents = %s;\n' "$tool_flag" ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$ADAPTER_DIR/opencode-plugin.js"
}
case "$action" in
    status)
        if [ "$managed" = 0 ]; then adapter_record not_installed 'no managed plugin'
        elif generate_plugin | cmp -s - "$config"; then adapter_record installed 'plugin matches this path'
        else adapter_record partial 'plugin changed or path drift; run install to repair'; fi
        ;;
    install)
        [ ! -f "$config" ] || [ "$managed" = 1 ] || adapter_error 'unmanaged plugin at destination; left unchanged'
        adapter_lock
        generate_plugin > "$temp"
        adapter_replace
        adapter_record installed 'root-session plugin configured; restart OpenCode'
        ;;
    remove)
        [ "$managed" = 1 ] || { adapter_record not_installed 'no managed plugin'; exit 0; }
        adapter_lock
        backup="$config.bak-$(date +%s)-$$"
        cp -p "$config" "$backup"
        chmod 600 "$backup"
        rm -f "$config"
        adapter_record not_installed 'managed plugin removed'
        ;;
esac
