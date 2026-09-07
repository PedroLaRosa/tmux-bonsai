#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
setup_test
export TMUX_CONF="$TMP/tmux.conf"
printf 'set -g @install-user kept\n' > "$TMUX_CONF"
destination="$TMP/install 'quoted' \"double\" \$literal"
# macOS ships Bash 3.2 even when PATH finds a newer Homebrew Bash. Exercise
# the platform shell explicitly so its replacement/quoting rules stay covered.
/bin/bash "$TEST_ROOT/install.sh" "$destination" --bin > "$TMP/install-output"
assert_contains "$(cat "$TMUX_CONF")" '@install-user kept'
[ -f "$destination/scripts/_reduce.jq" ]
[ -f "$destination/scripts/adapters/opencode-plugin.js" ]
[ -x "$destination/scripts/hooks/hook-claude.sh" ]
assert_contains "$("$HOME/.local/bin/bonsai" help)" 'Usage: bonsai'
tmx set -gu @bonsai-version
if ! tmx source-file "$TMUX_CONF" > "$TMP/source-output" 2>&1; then
  cat "$TMP/source-output" >&2
  printf 'Installer loader config:\n' >&2
  cat "$TMUX_CONF" >&2
  # run-shell normally discards stderr. Re-run the installed entrypoint with
  # stderr forwarded into its stdout, which the waiting tmux client can print.
  printf 'Installed plugin diagnostic (stderr included):\n' >&2
  tmx run-shell "$(bonsai_shell_quote "$destination/bonsai.tmux") 2>&1" >&2 || true
  exit 1
fi
assert_eq 1.0 "$(tmx show -gqv @bonsai-version)" 'quoted loader initializes plugin'
assert_eq kept "$(tmx show -gqv @install-user)"
before=$(cat "$TMUX_CONF")
bash "$TEST_ROOT/install.sh" "$destination" --bin > "$TMP/install-output"
assert_eq "$before" "$(cat "$TMUX_CONF")" 'idempotent installer'
