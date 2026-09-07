#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane=${1:-}; [ -n "$pane" ] || { echo 'usage: bonsai reply PANE [TEXT] [--yes] [--no-enter]' >&2; exit 2; }
shift
yes=off enter=on text='' supplied=off waiting_only=off resume=off
while [ "$#" -gt 0 ]; do
 case "$1" in
  --yes) yes=on;; --enter) enter=on;; --no-enter) enter=off;; --waiting-only) waiting_only=on;; --resume) resume=on;;
  --) shift; text="$*"; supplied=on; break;;
  *) if [ "$supplied" = on ]; then text="$text $1"; else text=$1; supplied=on; fi;;
 esac; shift
done
reply_allowed() {
 local state
 state=$("$BONSAI_SCRIPTS/list.sh" --json --all | jq -er --arg pane "$pane" '.[]|select(.pane_id==$pane)|.state') || {
  echo "pane $pane no longer exists" >&2; return 1;
 }
 if [ "$resume" = on ]; then [ "$state" = exited ] && return 0
 elif [ "$waiting_only" = on ]; then [ "$state" = waiting ] && return 0
 else case "$state" in waiting|done|idle|stopped) return 0;; esac; fi
 echo "Cannot send input to $pane while its state is $state." >&2
 return 1
}
reply_allowed || exit 1
if [ "$supplied" = off ]; then printf 'Reply to %s: ' "$pane"; IFS='' read -r text || exit 1; fi
[ -n "$text" ] || exit 0
if [ "$yes" != on ]; then
 suffix=''; [ "$enter" = off ] || suffix=' and press Enter'
 printf '\nSend literally to %s%s:\n%s\nConfirm [y/N]: ' "$pane" "$suffix" "$text"
 IFS='' read -r answer || exit 1
 case "$answer" in y|Y|yes) :;; *) exit 1;; esac
fi
if [ "$yes" != on ] || [ "$supplied" = off ]; then reply_allowed || exit 1; fi
# Text is never parsed as key names or a shell command.
tmx send-keys -t "$pane" -l -- "$text" || exit 1
[ "$enter" = off ] || tmx send-keys -t "$pane" Enter
