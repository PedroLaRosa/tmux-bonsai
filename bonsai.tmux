#!/usr/bin/env bash
# tmux-bonsai — self-contained git worktree management for tmux.
# Agent notifications + the jump-board dashboard live in the companion plugin
# tmux-agent-notify (https://github.com/PedroLaRosa/tmux-agent-notify).
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
key="$(tmux show-option -gqv @bonsai-key)"; key="${key:-W}"
tmux bind-key "$key" run-shell "$CURRENT_DIR/scripts/menu.sh"
