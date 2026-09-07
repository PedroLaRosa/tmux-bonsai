#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TEST_ROOT/scripts/_lib.sh"
assert_eq() { [ "$1" = "$2" ] || { printf 'FAIL %s: expected <%s>, got <%s>\n' "${3:-assert_eq}" "$1" "$2" >&2; exit 1; }; }
assert_contains() { case "$1" in *"$2"*) ;; *) printf 'FAIL: missing <%s> in <%s>\n' "$2" "$1" >&2; exit 1;; esac; }
assert_jq() { printf '%s' "$1" | jq -e "$2" >/dev/null || { printf 'FAIL jq %s: %s\n' "$2" "$1" >&2; exit 1; }; }
setup_test() {
  TMP=$(mktemp -d "${BONSAI_TEST_TMP:-${TMPDIR:-/tmp}}/case.XXXXXX")
  export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  export TMUX="${BONSAI_SOCKET},0,0"
  tmx set -g @bonsai-state-dir "$XDG_STATE_HOME/tmux-bonsai" \; set -g @bonsai-config-dir "$XDG_CONFIG_HOME/tmux-bonsai" \; set -g @bonsai-notify off \; set -g @bonsai-notify-remind off
  export BONSAI_SCRIPTS="$TEST_ROOT/scripts"
}
test_pane() { tmx new-window -d -P -F '#{pane_id}' -c "${1:-$TMP}" 'sleep 3600'; }
