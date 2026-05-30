#!/usr/bin/env bash
S="$(cd "$(dirname "$0")" && pwd)"
tmux display-menu -T "#[align=centre] bonsai " \
  "new worktree"            n "display-popup -d '#{pane_current_path}' -E '$S/new.sh'" \
  "new worktree + agent"    a "display-popup -d '#{pane_current_path}' -E '$S/new.sh agent'" \
  "open / switch"           o "display-popup -d '#{pane_current_path}' -E '$S/switch.sh'" \
  "" \
  "worktree as window"      w "display-popup -d '#{pane_current_path}' -E '$S/window.sh'" \
  "worktree as window + agent" W "display-popup -d '#{pane_current_path}' -E '$S/window.sh agent'" \
  "promote window->session" r "run-shell '$S/promote.sh'" \
  "" \
  "list worktrees"          L "display-popup -d '#{pane_current_path}' -E '$S/list.sh'" \
  "setup notifications"     N "display-popup -d '#{pane_current_path}' -E '$S/install-notify.sh'" \
  "clear agent markers"     c "run-shell '$S/clear-markers.sh'" \
  "" \
  "remove current"          x "confirm-before -p 'remove this worktree? (y/n) ' \"run-shell '$S/remove.sh'\"" \
  "prune merged"            X "confirm-before -p 'prune merged worktrees? (y/n) ' \"display-popup -d '#{pane_current_path}' -E '$S/prune.sh'\""
