#!/usr/bin/env bash
# Install tmux-worktrunk locally (no TPM needed).
# Usage: ./install.sh [target-dir]   (default: ~/.tmux/plugins/tmux-worktrunk)
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEST="${1:-$HOME/.tmux/plugins/tmux-worktrunk}"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"

echo "Installing tmux-worktrunk"
echo "  from: $SRC"
echo "  to:   $DEST"

mkdir -p "$DEST/scripts"
cp "$SRC/worktrunk.tmux" "$DEST/"
cp "$SRC/README.md" "$DEST/" 2>/dev/null || true
cp "$SRC/scripts/"*.sh "$DEST/scripts/"
chmod +x "$DEST/worktrunk.tmux" "$DEST/scripts/"*.sh
echo "  ✓ copied files"

if [ -f "$TMUX_CONF" ] && grep -qF "$DEST/worktrunk.tmux" "$TMUX_CONF"; then
  echo "  ✓ $TMUX_CONF already loads the plugin"
else
  {
    echo ""
    echo "# tmux-worktrunk"
    echo "set -g @worktrunk-key     'W'"
    echo "set -g @worktrunk-agent   'claude'"
    echo "set -g @worktrunk-windows 'edit agent serve git'"
    echo "set -g @worktrunk-notify  'on'"
    echo "run-shell '$DEST/worktrunk.tmux'"
  } >> "$TMUX_CONF"
  echo "  ✓ appended config + loader to $TMUX_CONF"
fi

if tmux info >/dev/null 2>&1; then
  tmux source-file "$TMUX_CONF" >/dev/null 2>&1 && echo "  ✓ reloaded running tmux"
fi

echo ""
echo "Dependency check:"
printf '  tmux (>=3.2)  : %s\n' "$(tmux -V 2>/dev/null || echo 'NOT FOUND')"
printf '  worktrunk (wt): %s\n' "$(command -v wt    || echo 'NOT FOUND - install worktrunk')"
printf '  fzf           : %s\n' "$(command -v fzf   || echo 'NOT FOUND - needed for open/switch')"
printf '  gh or glab    : %s\n' "$(command -v gh || command -v glab || echo 'NOT FOUND - needed for open PR')"
printf '  jq            : %s\n' "$(command -v jq    || echo 'NOT FOUND - needed for notification setup')"

KEY="$(tmux show-option -gqv @worktrunk-key 2>/dev/null)"; KEY="${KEY:-W}"
echo ""
echo "Done. Open the menu with:  <prefix> + $KEY"
echo "Wire up agent notifications from the menu (\"setup notifications\"), or run:"
echo "  $DEST/scripts/install-notify.sh"
