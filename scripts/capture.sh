#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane=${1:-}; [ -n "$pane" ] || { echo 'usage: bonsai capture PANE [-S -200]' >&2; exit 2; }
shift
start=-80
while [ "$#" -gt 0 ]; do
 case "$1" in -S) [ "$#" -ge 2 ] || exit 2; start=$2; shift;; *) echo "unknown capture option: $1" >&2; exit 2;; esac
 shift
done
tmx capture-pane -p -e -t "$pane" -S "$start"
