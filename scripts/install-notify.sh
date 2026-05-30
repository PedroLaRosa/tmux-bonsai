#!/usr/bin/env bash
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
NOTIFY="$S/notify.sh"

echo "Wiring agent notifications -> $NOTIFY"
echo

# --- Claude Code: merge Stop + Notification hooks into ~/.claude/settings.json ---
if command -v jq >/dev/null 2>&1; then
  CC="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"; [ -f "$CC" ] || echo '{}' > "$CC"
  tmp=$(mktemp)
  jq --arg n "$NOTIFY" '
    .hooks //= {}
    | .hooks.Stop = ((.hooks.Stop // []) + [{"matcher":"","hooks":[{"type":"command","command":($n+" done")}]}])
    | .hooks.Notification = ((.hooks.Notification // []) + [{"matcher":"","hooks":[{"type":"command","command":($n+" waiting")}]}])
  ' "$CC" > "$tmp" && mv "$tmp" "$CC" && echo "  ✓ Claude Code: $CC"
else
  echo "  ! jq not found — skipping Claude Code (install jq, then re-run)"
fi

# --- opencode: drop an auto-loaded plugin ---
OCP="$HOME/.config/opencode/plugin"
mkdir -p "$OCP"
cat > "$OCP/wt-notify.js" <<'JS'
// Auto-loaded opencode plugin: forwards session events to the tmux notifier.
export const WtNotify = async ({ $ }) => ({
  event: async ({ event }) => {
    const map = { "session.idle": "done", "session.error": "error" };
    const state = map[event.type];
    if (state) { try { await $`__NOTIFY__ ${state}`; } catch (e) {} }
  }
});
JS
sed -i "s#__NOTIFY__#$NOTIFY#" "$OCP/wt-notify.js"
echo "  ✓ opencode:    $OCP/wt-notify.js"
echo "    (if opencode doesn't load it, try ~/.config/opencode/plugins/ — dir name varies by version)"

echo
echo "Last step: in ~/.tmux.conf add   set -g @bonsai-notify on   then reload."
echo
read -rn1 -p "[any key to close]"
