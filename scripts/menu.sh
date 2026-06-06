#!/usr/bin/env bash
S="$(cd "$(dirname "$0")" && pwd)"
tmux display-menu -T "#[align=centre] bonsai " -- \
  "-#[align=centre]Session" "" "" \
  "new session worktree" n "run-shell -b '$S/launch.sh new.sh'" \
  "new session worktree + agent" a "run-shell -b '$S/launch.sh new.sh agent'" \
  "open / switch session worktree" o "run-shell -b '$S/launch.sh switch.sh'" \
  "" \
  "-#[align=centre]Window" "" "" \
  "new window worktree" w "run-shell -b '$S/launch.sh window.sh'" \
  "new window worktree + agent" W "run-shell -b '$S/launch.sh window.sh agent'" \
  "promote window->session" r "run-shell '$S/promote.sh'" \
  "" \
  "-#[align=centre]Pane" "" "" \
  "split pane right + agent" "|" "run-shell '$S/split.sh -h'" \
  "split pane down + agent" "_" "run-shell '$S/split.sh -v'" \
  "" \
  "-#[align=centre]Notify" "" "" \
  "dashboard (jump board)" d "run-shell -b '$S/launch.sh dashboard.sh'" \
  "list worktrees" L "run-shell -b '$S/launch.sh list.sh'" \
  "setup notifications" N "run-shell -b '$S/launch.sh install-notify.sh'" \
  "clear agent markers" c "run-shell '$S/clear-markers.sh'" \
  "" \
  "-#[align=centre]Remove" "" "" \
  "remove current worktree" x "confirm-before -p 'remove this worktree? (y/n) ' \"run-shell '$S/remove.sh'\""
