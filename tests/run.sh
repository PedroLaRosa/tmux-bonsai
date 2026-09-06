#!/usr/bin/env bash
# Run the whole suite: shellcheck over every shell file, then bats.
#   tests/run.sh              everything
#   tests/run.sh lint         shellcheck only
#   tests/run.sh state.bats   one file
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
status=0

shell_files() {
  printf '%s\n' bonsai.tmux install.sh scripts/bonsai
  find scripts tests -name '*.sh' -o -name '*.bash' | sort
}

run_lint() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "· shellcheck not installed — skipping lint"
    return 0
  fi
  echo "== shellcheck =="
  local f rc=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    shellcheck -s bash -S warning -e SC1090,SC1091 "$f" || rc=1
  done < <(shell_files)
  [ "$rc" -eq 0 ] && echo "  ✓ clean"
  return $rc
}

run_syntax() {
  echo "== bash -n =="
  local f rc=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    bash -n "$f" || { echo "  ✗ $f"; rc=1; }
  done < <(shell_files)
  [ "$rc" -eq 0 ] && echo "  ✓ clean"
  return $rc
}

run_bats() {
  if ! command -v bats >/dev/null 2>&1; then
    echo "· bats not installed — skipping tests (https://bats-core.readthedocs.io)"
    return 0
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    echo "· tmux not installed — skipping tests"
    return 0
  fi
  echo "== bats =="
  if [ $# -gt 0 ]; then
    bats "$@"
  else
    bats tests/*.bats
  fi
}

case "${1:-all}" in
  lint)   run_lint; exit $? ;;
  syntax) run_syntax; exit $? ;;
  all)    run_syntax || status=1; run_lint || status=1; run_bats || status=1 ;;
  *)      run_bats "$@" || status=1 ;;
esac
exit $status
