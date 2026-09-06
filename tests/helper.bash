#!/usr/bin/env bash
# Common bats setup: every test file gets its own tmux server, its own XDG
# state/config directories and its own $HOME, so nothing touches the developer's
# real tmux, real ~/.claude/settings.json or real events log.

bonsai_repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P; }

bonsai_setup_server() {
  BONSAI_REPO="$(bonsai_repo_root)"
  BONSAI_SCRIPTS="$BONSAI_REPO/scripts"
  BATS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/bonsai-test.XXXXXX")"
  BONSAI_TEST_LABEL="bonsai-test-$$-${RANDOM:-0}"

  export BONSAI_REPO BONSAI_SCRIPTS BATS_TMP BONSAI_TEST_LABEL
  export XDG_STATE_HOME="$BATS_TMP/state"
  export XDG_CONFIG_HOME="$BATS_TMP/config"
  export HOME="$BATS_TMP/home"
  mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$HOME"

  # A UTF-8 locale, without which tmux renders every non-ASCII byte as `_`.
  if [ -z "${LC_ALL:-}${LC_CTYPE:-}" ]; then
    for c in C.UTF-8 C.utf8 en_US.UTF-8; do
      if locale -a 2>/dev/null | grep -qxF "$c"; then export LC_CTYPE="$c"; break; fi
    done
  fi

  command tmux -L "$BONSAI_TEST_LABEL" -f /dev/null new-session -d -s main -x 200 -y 50
  BONSAI_SOCKET="$(command tmux -L "$BONSAI_TEST_LABEL" display-message -p '#{socket_path}')"
  export BONSAI_SOCKET
}

bonsai_teardown_server() {
  command tmux -L "$BONSAI_TEST_LABEL" kill-server 2>/dev/null || true
  [ -n "${BATS_TMP:-}" ] && rm -rf "$BATS_TMP"
  return 0
}

# tmux on the test server.
t() { command tmux -L "$BONSAI_TEST_LABEL" "$@"; }

# The plugin CLI, always pointed at the test server.
bonsai() { "$BONSAI_SCRIPTS/bonsai" -S "$BONSAI_SOCKET" "$@"; }

# Make a fresh pane and print its id.
new_pane() {
  t new-window -P -F '#{pane_id}' -d "${1:-sh -c 'while :; do sleep 5; done'}"
}

pane_opt() { t display-message -p -t "$1" "#{$2}"; }

# Wait until a shell condition holds, up to N tenths of a second. Detached work
# (the reducer, notify sleepers) is asynchronous by design, so tests poll rather
# than sleeping a fixed amount.
wait_for() {                                      # TENTHS 'shell test'
  local tries="${1:-30}" cond="$2" i=0
  while [ "$i" -lt "$tries" ]; do
    if eval "$cond"; then return 0; fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}
