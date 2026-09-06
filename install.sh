#!/usr/bin/env bash
# Install tmux-bonsai locally (no TPM needed).
# Usage: ./install.sh [target-dir]   (default: ~/.tmux/plugins/tmux-bonsai)
#
# Everything here is optional except copying the files: the plugin works with
# tmux alone, gains the board with fzf, gains agent hooks with jq, and gains
# desktop banners with a notification backend. The dependency report at the end
# says which of those you have, and `bonsai doctor` says it in more detail
# later.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
DEST="${1:-$HOME/.tmux/plugins/tmux-bonsai}"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"

echo "Installing tmux-bonsai"
echo "  from: $SRC"
echo "  to:   $DEST"

mkdir -p "$DEST/scripts/hooks" "$DEST/scripts/adapters" "$DEST/docs"
cp "$SRC/bonsai.tmux" "$DEST/"
cp "$SRC/README.md" "$DEST/" 2>/dev/null || true
cp "$SRC/scripts/bonsai" "$DEST/scripts/"
cp "$SRC/scripts/"*.sh "$DEST/scripts/"
cp "$SRC/scripts/hooks/"* "$DEST/scripts/hooks/" 2>/dev/null || true
cp "$SRC/scripts/adapters/"* "$DEST/scripts/adapters/" 2>/dev/null || true
cp "$SRC/docs/"*.md "$DEST/docs/" 2>/dev/null || true
chmod +x "$DEST/bonsai.tmux" "$DEST/scripts/bonsai" "$DEST/scripts/"*.sh 2>/dev/null
chmod +x "$DEST/scripts/hooks/"*.sh "$DEST/scripts/adapters/"*.sh 2>/dev/null
echo "  ✓ copied files"

if [ -f "$TMUX_CONF" ] && grep -qF "$DEST/bonsai.tmux" "$TMUX_CONF"; then
  echo "  ✓ $TMUX_CONF already loads the plugin"
else
  {
    echo ""
    echo "# tmux-bonsai"
    echo "set -g @bonsai-key     'W'"
    echo "set -g @bonsai-agent   'claude'"
    echo "run-shell '$DEST/bonsai.tmux'"
  } >> "$TMUX_CONF"
  echo "  ✓ appended config + loader to $TMUX_CONF"
fi

# A `bonsai` on PATH is what makes the CLI and the orchestration primitives
# usable from a shell and from scripts. Offered, never forced: the plugin itself
# always calls the copy inside $DEST by absolute path.
BIN_DIR="$HOME/.local/bin"
if [ -t 0 ] && [ ! -e "$BIN_DIR/bonsai" ]; then
  printf '  Link %s/bonsai -> the CLI? [y/N] ' "$BIN_DIR"
  read -r reply
  case "$reply" in
    [yY]*)
      mkdir -p "$BIN_DIR" && ln -sf "$DEST/scripts/bonsai" "$BIN_DIR/bonsai" \
        && echo "  ✓ linked $BIN_DIR/bonsai"
      case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) echo "  ⚠ $BIN_DIR is not on your PATH — add it to use \`bonsai\` directly" ;;
      esac ;;
    *) echo "  · skipped (run: ln -s $DEST/scripts/bonsai $BIN_DIR/bonsai)" ;;
  esac
fi

if tmux info >/dev/null 2>&1; then
  tmux source-file "$TMUX_CONF" >/dev/null 2>&1 && echo "  ✓ reloaded running tmux"
fi

# ---------------------------------------------------------------- dependencies

have() { command -v "$1" >/dev/null 2>&1; }
report() {                                        # LABEL COMMAND NOTE
  if have "$2"; then
    printf '  ✓ %-14s %s\n' "$1" "$(command -v "$2")"
  else
    printf '  ✗ %-14s not found — %s\n' "$1" "$3"
  fi
}

echo ""
echo "Dependencies:"
printf '  %s %-14s %s\n' "$(have tmux && echo ✓ || echo ✗)" "tmux (>=3.2)" "$(tmux -V 2>/dev/null || echo 'NOT FOUND')"
report "worktrunk (wt)" wt   "needed for the worktree commands: https://github.com/dmmulroy/worktrunk"
report "fzf"            fzf  "needed for the agent board and worktree picker"
report "jq"             jq   "needed to install agent hooks"
report "curl"           curl "used for the board's instant refresh (falls back to a timer)"

echo ""
echo "Notification backend:"
backend=''
case "$(uname -s)" in
  Darwin)
    for c in terminal-notifier alerter osascript; do
      have "$c" && { backend="$c"; break; }
    done
    [ -z "$backend" ] && echo "  ✗ none — install one: brew install terminal-notifier" ;;
  Linux)
    for c in notify-send dunstify gdbus; do
      have "$c" && { backend="$c"; break; }
    done
    [ -z "$backend" ] && echo "  ✗ none — install one: apt install libnotify-bin" ;;
  *) echo "  · unknown platform — bonsai doctor will suggest a backend" ;;
esac
[ -n "$backend" ] && printf '  ✓ %s\n' "$backend"

KEY="$(tmux show-option -gqv @bonsai-key 2>/dev/null)"; KEY="${KEY:-W}"
echo ""
echo "Done. Open the menu with:  <prefix> + $KEY"
echo "Next: <prefix> + $KEY → Notifications → setup / repair agent hooks"
echo "      wires your agents' hooks and sends a test notification."
echo "Diagnose anything with:  $DEST/scripts/bonsai doctor"
