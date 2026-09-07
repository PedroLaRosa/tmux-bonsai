#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
setup_test
export TMUX_CONF="$TMP/tmux.conf"
printf 'set -g @install-user kept\n' > "$TMUX_CONF"
destination="$TMP/install 'quoted' \"double\" \$literal"
bash "$TEST_ROOT/install.sh" "$destination" --bin > "$TMP/install-output"
assert_contains "$(cat "$TMUX_CONF")" '@install-user kept'
[ -f "$destination/scripts/_reduce.jq" ]
[ -f "$destination/scripts/adapters/opencode-plugin.js" ]
[ -x "$destination/scripts/hooks/hook-claude.sh" ]
assert_contains "$("$HOME/.local/bin/bonsai" help)" 'Usage: bonsai'
tmx source-file "$TMUX_CONF"
assert_eq kept "$(tmx show -gqv @install-user)"
before=$(cat "$TMUX_CONF")
bash "$TEST_ROOT/install.sh" "$destination" --bin > "$TMP/install-output"
assert_eq "$before" "$(cat "$TMUX_CONF")" 'idempotent installer'
