#!/usr/bin/env bash
# A bounded, top-level TOML assignment. Existing user notify commands win.
agent=codex; cli=codex; shape=toml
config=${CODEX_HOME:-$HOME/.codex}/config.toml
# shellcheck source=_common.sh
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
if [ "$action" = explain ]; then
    adapter_record installed 'notify tracks completed turns. Existing notify commands are preserved; use codex-hooks for native lifecycle tracking and review it in Codex /hooks.'
    printf '%s\n' 'https://learn.chatgpt.com/docs/config-file/config-reference' 'https://learn.chatgpt.com/docs/hooks'
    exit 0
fi
adapter_check
notify_line="notify = $(jq -cn --arg path "$ADAPTER_SCRIPTS/hooks/hook-codex-notify.sh" '[$path]')"
start='# tmux-bonsai notify begin'; end='# tmux-bonsai notify end'
content=
[ ! -f "$config" ] || content=$(cat "$config")
# Only modify our exact three-line block. Refuse an edited block instead of
# discarding an unrelated setting inserted by the user.
marker_count=$(printf '%s\n' "$content" | awk -v start="$start" -v end="$end" '$0==start || $0==end {n++} END {print n+0}')
managed=$(printf '%s\n' "$content" | awk -v start="$start" -v end="$end" 'NR==1 && $0==start {first=1} NR==2 {line=$0} NR==3 && first && $0==end {print line}')
if [ "$marker_count" != 0 ] && { [ "$marker_count" != 2 ] || [ -z "$managed" ]; }; then
    adapter_error 'managed notify block markers were edited; config left unchanged'
fi
if [ -n "$managed" ]; then
    [ "$(printf '%s\n' "$managed" | wc -l | tr -d ' ')" = 1 ] || adapter_error 'managed notify block was edited; repair it manually'
    case "$managed" in 'notify = ['*'/scripts/hooks/hook-codex-notify.sh"'']') ;; *) adapter_error 'managed notify block was edited; repair it manually' ;; esac
fi
case "$action" in
    status)
        if [ "$managed" = "$notify_line" ] && [ -x "$ADAPTER_SCRIPTS/hooks/hook-codex-notify.sh" ]; then adapter_record installed 'turn completion configured; working state uses title evidence'
        elif [ -n "$managed" ]; then adapter_record partial 'plugin path drift; run install to repair'
        else adapter_record not_installed 'no managed notify command'; fi
        ;;
    install|remove)
        [ "$action" != remove ] || [ -n "$managed" ] || { adapter_record not_installed 'no managed notify command'; exit 0; }
        adapter_lock
        # Work on bytes from the file (preserve trailing newlines and comments).
        if [ -f "$config" ]; then
            awk -v start="$start" -v end="$end" '$0==start {inside=1;next} $0==end {inside=0;next} !inside {print}' "$config" > "$temp"
        else : > "$temp"; fi
        if [ "$action" = install ]; then
            # Conservative detection also refuses a table-scoped notify key.
            # This avoids guessing about arbitrary TOML or composing commands.
            if awk '/^[[:space:]]*(notify|"notify"|\047notify\047)[[:space:]]*=/ {found=1} END {exit !found}' "$temp"; then
                adapter_error 'existing notify setting preserved; use codex-hooks or compose commands yourself'
            fi
            content=$(cat "$temp")
            { printf '%s\n%s\n%s\n' "$start" "$notify_line" "$end"; [ -z "$content" ] || printf '%s\n' "$content"; } > "$temp"
        fi
        adapter_replace
        if [ "$action" = install ]; then adapter_record installed 'turn completion configured; restart Codex'
        else adapter_record not_installed 'managed notify command removed'; fi
        ;;
esac
