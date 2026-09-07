#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"
command -v jq >/dev/null 2>&1 || { echo 'Install jq before setting up hooks.'; read -r _; wt_back; }
echo 'Agent hook setup — configs are backed up before changes.'
"$BONSAI_SCRIPTS/bonsai" hooks status
echo 'Optional: codex-hooks (trust through /hooks); claude-statusline (preserves your command).'
echo
printf 'Agents to install (space-separated names, blank cancels): '
IFS= read -r selected || wt_back
[ -n "$selected" ] || wt_back
read -r -a agents <<< "$selected"
# This explicit selection is the only path from the wizard to config mutation.
if ! "$BONSAI_SCRIPTS/bonsai" hooks install "${agents[@]}"; then
  echo 'Some hooks need repair; inspect the error details above before relying on alerts.'
fi
case " $selected " in *" claude "*)
  printf "Also enable Claude's own terminal bell? [y/N] "; read -r answer
  if [[ "$answer" = y || "$answer" = Y ]]; then
    "$BONSAI_SCRIPTS/adapters/claude.sh" install --terminal-bell
  fi;;
esac
printf '\nEnable tmux focus reporting? [y/N] '; read -r answer
if [[ "$answer" = y || "$answer" = Y ]]; then
  "$BONSAI_SCRIPTS/settings.sh" prerequisite focus-events on
fi
if bonsai_tmux_at_least 3.3; then
  printf 'Enable terminal notification passthrough for hidden panes? [y/N] '; read -r answer
  if [[ "$answer" = y || "$answer" = Y ]]; then
    "$BONSAI_SCRIPTS/settings.sh" prerequisite allow-passthrough all
  fi
fi
printf 'Send a test notification now? [Y/n] '; read -r answer
case "$answer" in n|N) wt_back;; *) exec "$BONSAI_SCRIPTS/notify-test.sh";; esac
