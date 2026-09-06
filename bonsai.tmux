#!/usr/bin/env bash
# tmux-bonsai — self-contained git worktree management for tmux.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
key="$(tmux show-option -gqv @bonsai-key)"; key="${key:-W}"
tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/menu.sh"

# Defaults are only applied when users have not supplied an option.
bonsai_default() { [ -n "$(tmux show-option -gqv "$1")" ] || tmux set-option -gq "$1" "$2"; }
bonsai_default @bonsai-notify on
bonsai_default @bonsai-notify-finished on
bonsai_default @bonsai-notify-input on
bonsai_default @bonsai-notify-error on
bonsai_default @bonsai-notify-focus strict
bonsai_default @bonsai-notify-backend auto
bonsai_default @bonsai-titlewatch on
bonsai_default @bonsai-state-dir "${XDG_STATE_HOME:-$HOME/.local/state}/tmux-bonsai"
tmux set-option -gq @bonsai-version "0.2.0"

# A private array index preserves user hooks and makes plugin reloads idempotent.
ack="run-shell -b '$CURRENT_DIR/scripts/ack.sh #{pane_id}'"
title="if-shell -F '#{==:#{@bonsai-titlewatch},on}' \"run-shell -b '$CURRENT_DIR/scripts/title.sh #{pane_id}'\""
for hook in after-select-pane after-select-window client-session-changed client-attached client-focus-in; do
  tmux set-hook -g "${hook}[991]" "$ack"
done
tmux set-hook -g "pane-title-changed[991]" "$title"

board_key=$(tmux show-option -gqv @bonsai-board-key)
[ -z "$board_key" ] || tmux bind-key "$board_key" display-popup -E -w 80% -h 80% "$CURRENT_DIR/scripts/board.sh"
next_key=$(tmux show-option -gqv @bonsai-next-key)
[ -z "$next_key" ] || tmux bind-key -T root "$next_key" run-shell -b "$CURRENT_DIR/scripts/next.sh"
