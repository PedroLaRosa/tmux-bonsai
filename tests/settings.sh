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
