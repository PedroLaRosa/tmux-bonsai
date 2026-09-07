#!/usr/bin/env bash
S="$(cd "$(dirname "$0")" && pwd)"
source "$S/_lib.sh"
run() { bonsai_run_command -b "$@"; }
popup() { run "$S/launch.sh" "$@"; }
counts=$("$S/status.sh" 2>/dev/null)
tmx display-menu -T '#[align=centre] bonsai ' -- \
  '-#[align=centre]Session' '' '' \
  'new session worktree' n "$(popup new.sh)" \
  'new session worktree + agent' a "$(popup new.sh agent)" \
  'open / switch session worktree' o "$(popup switch.sh)" \
  '' \
  '-#[align=centre]Window' '' '' \
  'new window worktree' w "$(popup window.sh)" \
  'new window worktree + agent' W "$(popup window.sh agent)" \
  'open / switch window worktree' O "$(popup window-switch.sh)" \
  'promote window->session' r "$(run "$S/promote.sh")" \
  '' \
  '-#[align=centre]Pane' '' '' \
  'split pane right + agent' '|' "$(run "$S/split.sh" -h)" \
  'split pane down + agent' _ "$(run "$S/split.sh" -v)" \
  '' \
  "-#[align=centre]Agents $counts" '' '' \
  'agent board (popup)' d "$(popup board.sh)" \
  'agent board as window' D "$(run "$S/board.sh" --window)" \
  'agent board as side pane' B "$(run "$S/board.sh" --side)" \
  'jump to next needs-you' j "$(run "$S/next.sh")" \
  'back to previous session' J 'switch-client -l' \
  'activity feed' f "$(popup feed.sh)" \
  'mark current pane unread' u "$(run "$S/bonsai" unread '#{pane_id}')" \
  '' \
  '-#[align=centre]Notifications #{@bonsai-notify}' '' '' \
  'notification settings…' N "$(run "$S/notify-menu.sh")" \
  '' \
  'list worktrees' L "$(popup worktrees.sh)" \
  '' \
  '-#[align=centre]Remove' '' '' \
  'remove current worktree' x "confirm-before -p 'remove this worktree? (y/n)' $(bonsai_tmux_quote "$(run "$S/remove.sh")")"
