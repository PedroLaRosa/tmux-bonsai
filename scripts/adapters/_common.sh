#!/usr/bin/env bash
# Shared installer plumbing. Hook execution never sources this file.
set -e
ADAPTER_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)
. "$ADAPTER_DIR/../_lib.sh"
ADAPTER_SCRIPTS=$(cd "$ADAPTER_DIR/.." && pwd -P)
adapter_record() { printf '%s\t%s\t%s\t%s\n' "$agent" "$1" "$config" "$2"; }
adapter_error() { adapter_record error "$*"; exit 1; }
adapter_args() {
    action=${1:-status}; [ "$#" -eq 0 ] || shift
    force=0; tools_mode=${BONSAI_HOOKS_TOOL_EVENTS:-}
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            --tools) shift; tools_mode=${1:-} ;;
            *) adapter_error "unknown option: $1" ;;
        esac
        shift
    done
    case "$action" in install|status|remove|explain) ;; *) adapter_error 'expected install|status|remove|explain' ;; esac
    if [ -z "$tools_mode" ]; then
        tools_mode=$(bonsai_opt @bonsai-hooks-tool-events on 2>/dev/null) || tools_mode=on
    fi
    case "$tools_mode" in on|off) ;; *) adapter_error '--tools requires on or off' ;; esac
    config=${BONSAI_ADAPTER_CONFIG:-$config}
}
adapter_check() {
    command -v jq >/dev/null 2>&1 || adapter_error 'jq is required'
    if [ "$action" = install ] && [ "$force" = 0 ] && ! command -v "$cli" >/dev/null 2>&1; then
        adapter_record 'skipped(cli_not_found)' "install $cli first; --force configures ahead of installation"
        exit 0
    fi
    [ ! -L "$config" ] || adapter_error 'config is a symlink; edit its target explicitly with BONSAI_ADAPTER_CONFIG'
}
adapter_lock() {
    mkdir -p "${config%/*}"
    lock="$config.bonsai-lock"
    if ! mkdir "$lock" 2>/dev/null; then
        local owner
        owner=$(cat "$lock/pid" 2>/dev/null) || owner=
        case "$owner" in ''|*[!0-9]*) adapter_error 'another installer holds the config lock' ;; esac
        if kill -0 "$owner" 2>/dev/null; then adapter_error 'another installer holds the config lock'; fi
        rm -f "$lock/pid"
        rmdir "$lock" 2>/dev/null || adapter_error 'could not recover stale config lock'
        mkdir "$lock" || adapter_error 'another installer holds the config lock'
    fi
    printf '%s\n' "$$" > "$lock/pid"
    trap 'rm -f "${temp:-}" "$lock/pid"; rmdir "$lock" 2>/dev/null || :' EXIT
    temp=$(mktemp "$config.bonsai-XXXXXX")
    chmod 600 "$temp"
}
adapter_replace() {
    local backup
    if [ -f "$config" ] && cmp -s "$config" "$temp"; then return; fi
    if [ -f "$config" ]; then
        backup="$config.bak-$(date +%s)-$$"
        cp -p "$config" "$backup"
        chmod 600 "$backup"
    fi
    mv "$temp" "$config"
}
adapter_json_input() {
    if [ -f "$config" ]; then
        if [ "$shape" = droid ]; then jq '{hooks: .}' "$config"; else cat "$config"; fi
    else printf '{}\n'; fi
}
adapter_json() {
    local quoted expected current managed_count
    printf -v quoted '%q' "$ADAPTER_SCRIPTS/hooks/hook-$agent.sh"
    adapter_json_input | jq -e 'type == "object" and ((.hooks // {}) | type == "object")' >/dev/null 2>&1 || adapter_error 'invalid JSON config; left unchanged'
    case "$action" in
        status)
            current=$(adapter_json_input | jq -Sc --arg action inspect --arg agent "$agent" --arg command "$quoted" --arg events "$events" --arg shape "$shape" -f "$ADAPTER_DIR/_json.jq")
            managed_count=$(printf '%s' "$current" | jq length)
            if [ "$managed_count" -eq 0 ]; then adapter_record not_installed 'no managed hooks'; return; fi
            expected=$(printf '{}' | jq -c --arg action install --arg agent "$agent" --arg command "$quoted" --arg events "$events" --arg shape "$shape" -f "$ADAPTER_DIR/_json.jq" | jq -Sc --arg action inspect --arg agent "$agent" --arg command "$quoted" --arg events "$events" --arg shape "$shape" -f "$ADAPTER_DIR/_json.jq")
            if [ "$current" = "$expected" ] && [ -x "$ADAPTER_SCRIPTS/hooks/hook-$agent.sh" ]; then
                adapter_record installed "${installed_detail:-managed hooks match this plugin path}"
            else adapter_record partial 'missing/changed hooks or plugin path drift; run install to repair'; fi
            ;;
        install|remove)
            [ "$action" != remove ] || [ -f "$config" ] || { adapter_record not_installed 'no config'; return; }
            adapter_lock
            adapter_json_input | jq --arg action "$action" --arg agent "$agent" --arg command "$quoted" --arg events "$events" --arg shape "$shape" -f "$ADAPTER_DIR/_json.jq" > "$temp" || adapter_error 'cannot merge hooks; config left unchanged'
            if [ "$shape" = droid ]; then
                current=$(jq '.hooks // {}' "$temp")
                printf '%s\n' "$current" > "$temp"
            fi
            jq -e 'type == "object"' "$temp" >/dev/null || adapter_error 'invalid generated JSON'
            adapter_replace
            if [ "$action" = install ]; then adapter_record installed "${installed_detail:-hooks installed; restart the agent if needed}"
            else adapter_record not_installed 'managed hooks removed; user hooks preserved'; fi
            ;;
    esac
}
