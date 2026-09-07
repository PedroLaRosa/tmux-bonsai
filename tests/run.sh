#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for dependency in tmux jq; do command -v "$dependency" >/dev/null || { echo "Missing $dependency" >&2; exit 1; }; done
export BONSAI_TEST_TMP
BONSAI_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-test.XXXXXX")
export BONSAI_SOCKET="$BONSAI_TEST_TMP/tmux.sock"
cleanup() { tmux -S "$BONSAI_SOCKET" kill-server 2>/dev/null || true; rm -rf "$BONSAI_TEST_TMP"; }
trap cleanup EXIT INT TERM
TMUX='' tmux -S "$BONSAI_SOCKET" -f /dev/null new-session -d -s test
for suite in "$ROOT/tests/"*.sh; do
  case "$suite" in */run.sh|*/helper.sh|*/latency.sh) continue;; esac
  if [ $# -gt 0 ] && [ "${suite##*/}" != "$1.sh" ]; then continue; fi
  printf 'Testing %s\n' "${suite##*/}"
  bash "$suite"
done
printf 'All tests passed.\n'
