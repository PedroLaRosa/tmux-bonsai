#!/usr/bin/env bash
. "$(dirname "$0")/_lib.sh"
git worktree list
echo; read -rn1 -p "[any key to close]"
wt_back                          # informational — always return to the menu
