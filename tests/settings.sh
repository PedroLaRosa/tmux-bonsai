#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
setup_test
assert_eq 600 "$(bonsai_duration 10m)"
assert_eq 1.5 "$(bonsai_duration 1.5)"
if bonsai_duration '1;false' >/dev/null; then exit 1; fi
"$BONSAI_SCRIPTS/settings.sh" set notify off
assert_eq off "$(bonsai_opt @bonsai-notify)"
assert_contains "$(cat "$(bonsai_config_dir)/settings.tmux")" '@bonsai-notify'
"$BONSAI_SCRIPTS/settings.sh" set notify-focus attached
assert_eq attached "$(bonsai_opt @bonsai-notify-focus)"
if "$BONSAI_SCRIPTS/settings.sh" set notify-focus bogus 2>/dev/null; then exit 1; fi
"$BONSAI_SCRIPTS/settings.sh" set notify-command ''
assert_eq '' "$(bonsai_opt @bonsai-notify-command)"
"$BONSAI_SCRIPTS/settings.sh" prerequisite focus-events on
assert_contains "$(cat "$(bonsai_config_dir)/settings.tmux")" 'focus-events'
tmx set -g focus-events off
"$BONSAI_SCRIPTS/settings.sh" init
assert_eq on "$(tmx show-option -gqv focus-events)"
"$BONSAI_SCRIPTS/settings.sh" set notify-grace 0.2
"$BONSAI_SCRIPTS/settings.sh" init
assert_eq 0.2 "$(bonsai_opt @bonsai-notify-grace)"
tmx set -g @bonsai-notify-grace 0.7
"$BONSAI_SCRIPTS/settings.sh" init
assert_eq 0.7 "$(bonsai_opt @bonsai-notify-grace)" 'new direct config wins over persisted value'
assert_contains "$(bonsai_opt @bonsai-pinned)" '@bonsai-notify-grace'
