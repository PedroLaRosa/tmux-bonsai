#!/usr/bin/env bash
# Install tmux-bonsai locally (no TPM needed).
# Usage: ./install.sh [target-dir] [--bin] (optional ~/.local/bin/bonsai link)
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SRC/scripts/_lib.sh"
DEST="$HOME/.tmux/plugins/tmux-bonsai"
install_bin=off
for arg in "$@"; do case "$arg" in --bin) install_bin=on;; *) DEST=$arg;; esac; done
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"

echo "Installing tmux-bonsai"
echo "  from: $SRC"
echo "  to:   $DEST"

mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd)
if [ "$(cd "$DEST" && pwd)" != "$SRC" ]; then
cp "$SRC/bonsai.tmux" "$DEST/"
cp "$SRC/README.md" "$DEST/" 2>/dev/null || true
cp -R "$SRC/scripts" "$DEST/"
cp -R "$SRC/docs" "$DEST/"
fi
chmod +x "$DEST/bonsai.tmux" "$DEST/scripts/bonsai"
find "$DEST/scripts" -type f -name '*.sh' -exec chmod +x {} +
echo "  ✓ copied files"
if [ "$install_bin" = on ]; then
  mkdir -p "$HOME/.local/bin"
  if [ -e "$HOME/.local/bin/bonsai" ] || [ -L "$HOME/.local/bin/bonsai" ]; then
    echo '  bonsai already exists in ~/.local/bin; leaving it intact'
  else
    ln -s "$DEST/scripts/bonsai" "$HOME/.local/bin/bonsai"
    echo '  ✓ linked ~/.local/bin/bonsai'
  fi
fi

if [ -f "$TMUX_CONF" ] && grep -qF "$DEST/bonsai.tmux" "$TMUX_CONF"; then
  echo "  ✓ $TMUX_CONF already loads the plugin"
else
  {
    echo ""
    echo "# tmux-bonsai"
    echo "set -g @bonsai-key     'W'"
    echo "set -g @bonsai-agent   'claude'"
    printf 'run-shell %s\n' "$(bonsai_tmux_quote "$(bonsai_shell_quote "$DEST/bonsai.tmux")")"
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
printf '  jq            : %s\n' "$(command -v jq    || echo 'NOT FOUND - needed for agent state')"
printf '  curl          : %s\n' "$(command -v curl  || echo 'NOT FOUND - needed for live board refresh')"

KEY="$(tmux show-option -gqv @bonsai-key 2>/dev/null)"; KEY="${KEY:-W}"
echo ""
echo "Done. Open the menu with:  <prefix> + $KEY"
echo 'Open Notifications → setup / repair agent hooks to enable agent alerts.'
echo "Run $DEST/scripts/bonsai doctor to inspect dependencies and notification evidence."
echo 'Add --bin when installing to expose the bonsai CLI in ~/.local/bin.'
