#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
target='' text='' yes=off supplied=off enter=on
while [ "$#" -gt 0 ]; do
 case "$1" in
  --to) [ "$#" -ge 2 ] || exit 2; target=$2; shift;;
  --yes) yes=on;; --no-enter) enter=off;; --enter) enter=on;;
  --) shift; text="$*"; supplied=on; break;;
  *) if [ "$supplied" = on ]; then text="$text $1"; else text=$1; supplied=on; fi;;
 esac; shift
done
[ -n "$target" ] && [ "$supplied" = on ] || { echo 'usage: bonsai send --to PANE|@waiting|@idle|@all|@branch:NAME TEXT [--yes]' >&2; exit 2; }
case "$target" in
 @waiting|@idle|@all|@branch:*)
  panes=$("$BONSAI_SCRIPTS/list.sh" --json | jq -r --arg target "$target" '.[]|
   select($target=="@all" or ($target=="@waiting" and .state=="waiting") or ($target=="@idle" and .state=="idle")
   or (($target|startswith("@branch:")) and .branch==($target|ltrimstr("@branch:"))))|.pane_id') || exit 1;;
 @*) echo "unknown agent group: $target" >&2; exit 2;;
 *) panes=$(tmx display-message -p -t "$target" '#{pane_id}') || exit 1;;
esac
[ -n "$panes" ] || { echo 'bonsai send: no matching agents' >&2; exit 1; }
if [ "$yes" != on ]; then
 printf 'Send literally to these panes:\n%s\n\n%s\nConfirm [y/N]: ' "$panes" "$text"
 IFS='' read -r answer || exit 1; case "$answer" in y|Y|yes) :;; *) exit 1;; esac
fi
failed=0
while IFS='' read -r pane; do
 if [ "$enter" = off ]; then "$BONSAI_SCRIPTS/reply.sh" "$pane" --yes --no-enter -- "$text" || failed=1
 else "$BONSAI_SCRIPTS/reply.sh" "$pane" --yes -- "$text" || failed=1; fi
done <<< "$panes"
exit "$failed"
