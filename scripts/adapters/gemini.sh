#!/usr/bin/env bash
agent=gemini; cli=gemini; shape=gemini
config=$HOME/.gemini/settings.json
. "${BASH_SOURCE[0]%/*}/_common.sh"
adapter_args "$@"
events='BeforeAgent AfterAgent'
[ "$tools_mode" = off ] || events="$events BeforeTool AfterTool"
if [ "$action" = explain ]; then
    adapter_record installed 'BeforeAgent/AfterAgent track turns; terminal titles fill permission waits. Hook timeout is milliseconds for Gemini.'
    printf '%s\n' 'https://geminicli.com/docs/hooks/reference/'
    exit 0
fi
adapter_check
adapter_json
