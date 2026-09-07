#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane=${1:-}; [ -n "$pane" ] || { echo 'usage: bonsai reply PANE [TEXT] [--yes] [--no-enter]' >&2; exit 2; }
shift
yes=off enter=on text='' supplied=off waiting_only=off
while [ "$#" -gt 0 ]; do
 case "$1" in
  --yes) yes=on;; --enter) enter=on;; --no-enter) enter=off;; --waiting-only) waiting_only=on;;
  --) shift; text="$*"; supplied=on; break;;
  *) if [ "$supplied" = on ]; then text="$text $1"; else text=$1; supplied=on; fi;;
 esac; shift
done
tmx display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1 || { echo "pane $pane no longer exists" >&2; exit 1; }
if [ "$waiting_only" = on ] && [ "$(tmx show-option -pqv -t "$pane" @agent_state)" != waiting ]; then
 echo 'Send yes is only available for a waiting agent.' >&2; exit 1
fi
if [ "$supplied" = off ]; then printf 'Reply to %s: ' "$pane"; IFS='' read -r text || exit 1; fi
[ -n "$text" ] || exit 0
if [ "$yes" != on ]; then
 suffix=''; [ "$enter" = off ] || suffix=' and press Enter'
 printf '\nSend literally to %s%s:\n%s\nConfirm [y/N]: ' "$pane" "$suffix" "$text"
 IFS='' read -r answer || exit 1
 case "$answer" in y|Y|yes) :;; *) exit 1;; esac
fi
# Text is never parsed as key names or a shell command.
tmx send-keys -t "$pane" -l -- "$text" || exit 1
[ "$enter" = off ] || tmx send-keys -t "$pane" Enter
