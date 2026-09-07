#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/_state.sh"
direction=${1:-in}; tty=${2:-}
[ -n "$tty" ] || tty=$(tmx display-message -p '#{client_tty}' 2>/dev/null)
[ -n "$tty" ] || exit 0
file=$(bonsai_focus_file)
mkdir -p "$(dirname "$file")" || exit 0
tmx wait-for -L bonsai-focus 2>/dev/null || exit 0
trap 'tmx wait-for -U bonsai-focus >/dev/null 2>&1 || true' EXIT
temporary=$(mktemp "${file}.XXXXXX") || exit 0
if [ -f "$file" ]; then awk -v tty="$tty" '$0 != tty' "$file" > "$temporary"; fi
case "$direction" in in|focus-in|client-focus-in) printf '%s\n' "$tty" >> "$temporary" ;; esac
mv -f "$temporary" "$file"
tmx wait-for -U bonsai-focus 2>/dev/null || true
trap - EXIT
case "$direction" in
  in|focus-in|client-focus-in)
    pane=$(tmx list-clients -F $'#{client_tty}\t#{pane_id}' 2>/dev/null | awk -F '\t' -v tty="$tty" '$1 == tty {print $2; exit}')
    [ -z "$pane" ] || "$BONSAI_SCRIPTS/ack.sh" "$pane" ;;
esac
