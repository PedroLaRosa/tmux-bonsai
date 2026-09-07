#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
setup_test
# User hooks survive reload, managed hooks appear exactly once.
tmx set-hook -g after-select-pane 'set-option -g @user-hook-kept yes'
tmx set -g @bonsai-notify off
bash "$TEST_ROOT/bonsai.tmux"
first=$(tmx show-hooks -g)
bash "$TEST_ROOT/bonsai.tmux"
second=$(tmx show-hooks -g)
assert_eq "$first" "$second" 'reload preserves hooks without duplicates'
assert_contains "$second" '@user-hook-kept'
assert_contains "$second" 'tmux-hook.sh'
assert_eq off "$(bonsai_opt @bonsai-notify)" 'tmux.conf option pinned'
assert_contains "$(bonsai_opt @bonsai-pinned)" '@bonsai-notify'
assert_contains "$(tmx show-hooks -gw)" 'pane-title-changed'
# Public manual state command and diagnostic JSON use this server.
pane=$(test_pane)
"$BONSAI_SCRIPTS/bonsai" mark "$pane" waiting
assert_eq waiting "$(tmx show-option -pqv -t "$pane" @agent_state)"
assert_jq "$("$BONSAI_SCRIPTS/bonsai" doctor --json)" 'type=="array" and any(.[]; .name=="tmux")'
# Enabling optional status decorations does not duplicate the user's theme.
tmx set -g status-right 'theme' \; set -g @bonsai-status on \; set -g @bonsai-window-glyphs on
bash "$TEST_ROOT/bonsai.tmux"
status=$(tmx show-option -gqv status-right)
bash "$TEST_ROOT/bonsai.tmux"
assert_eq "$status" "$(tmx show-option -gqv status-right)"
assert_contains "$status" theme
