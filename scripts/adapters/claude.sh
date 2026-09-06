#!/usr/bin/env bash
set -eu
S=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
settings=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}; action=${1:-status}
marker='tmux-bonsai managed hook'
case $action in
  status) grep -q "$marker" "$settings" 2>/dev/null && echo 'Claude hooks: installed' || { echo 'Claude hooks: not installed'; exit 1; } ;;
  install)
    command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }
    mkdir -p "$(dirname "$settings")"; [ -f "$settings" ] || printf '{}\n' >"$settings"
    cp "$settings" "$settings.bonsai.bak"
    hook="$S/hooks/hook-claude.sh"
    tmp="$settings.tmp.$$"
    jq --arg command "$hook \$EVENT # tmux-bonsai managed hook" '
      reduce ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","PermissionRequest","Notification","Stop","StopFailure","PostCompact"][] as $e
        (.hooks = (.hooks // {});
         .hooks[$e] = (((.hooks[$e] // []) |
           map(select(.hooks | all((.command // "") | contains("tmux-bonsai managed hook") | not)))) +
           [{hooks:[{type:"command",command:($command|sub("\\$EVENT";$e)),timeout:5}]}]))
    ' "$settings" >"$tmp" && mv "$tmp" "$settings"
    echo "Claude hooks installed in $settings" ;;
  remove)
    command -v jq >/dev/null || exit 1; tmp="$settings.tmp.$$"
    jq --arg marker "$marker" 'if .hooks then .hooks |= with_entries(.value |= map(select(.hooks|all((.command // "")|contains($marker)|not)))) else . end' "$settings" >"$tmp" && mv "$tmp" "$settings"
    echo 'Claude hooks removed' ;;
  explain) echo "Installs managed command hooks in $settings for lifecycle, tool, permission, notification, and stop events." ;;
  *) echo 'usage: bonsai hooks install|remove|status|explain' >&2; exit 2 ;;
esac
