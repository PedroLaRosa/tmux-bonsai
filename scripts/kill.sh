#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane=${1:-}; [ -n "$pane" ] || { echo 'usage: bonsai kill PANE [--pane] [--yes]' >&2; exit 2; }
shift
kill_pane=off yes=off
for arg in "$@"; do case "$arg" in --pane) kill_pane=on;; --yes) yes=on;; *) exit 2;; esac; done
action='interrupt agent'; [ "$kill_pane" = off ] || action='permanently close pane'
if [ "$yes" != on ]; then
 printf '%s %s? [y/N]: ' "$action" "$pane"; IFS='' read -r answer || exit 1
 case "$answer" in y|Y|yes) :;; *) exit 1;; esac
fi
if [ "$kill_pane" = on ]; then tmx kill-pane -t "$pane"; else
 tmx send-keys -t "$pane" C-c || exit 1
 if [ "$yes" != on ]; then
  printf 'Also close pane %s permanently? [y/N]: ' "$pane"; IFS='' read -r answer || exit 0
  case "$answer" in y|Y|yes) tmx kill-pane -t "$pane";; esac
 fi
fi
