#!/usr/bin/env bash
# Single entry point for every tmux hook this plugin registers.
#
# Two reasons it exists rather than pointing each hook at its own script:
#   * the literal path fragment `hooks/tmux-hook.sh` is the marker bonsai.tmux
#     greps for when de-duplicating hooks on reload, so stale entries left by an
#     older install path are still recognised and removed;
#   * it keeps hook commands short, and tmux format-expands `#{pane_id}` in a
#     run-shell argument (verified on 3.4), so the pane always arrives here.
#
# Hooks fire on the tmux server's main loop. Nothing here may block: every
# action is either a single tmux call or a detached script.
set -uo pipefail
BONSAI_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)"
export BONSAI_SCRIPTS
# shellcheck source=scripts/_lib.sh
. "$BONSAI_SCRIPTS/_lib.sh"

action="${1:-}"; [ $# -gt 0 ] && shift

case "$action" in
  ack)    exec "$BONSAI_SCRIPTS/ack.sh" "$@" ;;
  focus)  exec "$BONSAI_SCRIPTS/focus.sh" "$@" ;;
  title)  exec "$BONSAI_SCRIPTS/title.sh" "$@" ;;
  bell)   exec "$BONSAI_SCRIPTS/notify.sh" bell "$@" ;;
  board)  exec "$BONSAI_SCRIPTS/board.sh" "$@" ;;
  *)      exit 0 ;;
esac
