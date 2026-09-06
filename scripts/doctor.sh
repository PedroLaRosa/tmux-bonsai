#!/usr/bin/env bash
set -u
S=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); . "$S/_lib.sh"
fail=0
check(){ if command -v "$1" >/dev/null 2>&1; then printf 'ok    %s: %s\n' "$1" "$(command -v "$1")"; else printf '%-5s %s\n' "$2" "$1"; [ "$2" = required ] && fail=1; fi; }
check tmux required; check jq required; check fzf optional
printf 'info  tmux: %s\n' "$(tmx -V 2>/dev/null || echo unavailable)"
backend=$($S/notify.sh backend 2>/dev/null || echo none); printf 'info  notification backend: %s\n' "$backend"
printf 'info  state directory: %s\n' "$(bonsai_state_dir)"
exit "$fail"
