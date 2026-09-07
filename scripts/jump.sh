#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
pane=${1:-}
[ -n "$pane" ] || { echo 'usage: bonsai jump PANE|@next' >&2; exit 2; }
[ "$pane" != @next ] || exec "$BONSAI_SCRIPTS/next.sh"
case "$pane" in
 worktree:*)
  branch=${pane#worktree:}; path=$(wt_path_of "$branch")
  [ -n "$path" ] || { echo "worktree $branch no longer exists" >&2; exit 1; }
  session=$(wt_ensure_session "$branch" "$path")
  pane=$(tmx display-message -p -t "$session:" '#{pane_id}') || exit 1;;
esac
record=$(tmx display-message -p -t "$pane" '#{pane_id} #{session_id} #{window_id}' 2>/dev/null) || {
 echo "bonsai: pane $pane no longer exists" >&2; exit 1;
}
read -r pane session window <<< "$record"
client=$(tmx list-clients -F '#{client_activity} #{client_tty}' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)
if [ -n "$client" ]; then tmx switch-client -c "$client" -t "$session" || exit 1; fi
tmx select-window -t "$window" \; select-pane -t "$pane" || exit 1
"$BONSAI_SCRIPTS/ack.sh" "$pane"
# Preserve pane styling when flashing the destination.
style=$(tmx show-options -pqv -t "$pane" window-style 2>/dev/null)
tmx select-pane -t "$pane" -P 'bg=colour237' 2>/dev/null || :
( sleep 0.15; tmx select-pane -t "$pane" -P "${style:-default}" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
tmx display-message "bonsai: jumped to $pane"
terminal=$(bonsai_opt @bonsai-terminal auto)
if [ "$terminal" = auto ]; then
 terminal=$(tmx show-environment -g TERM_PROGRAM 2>/dev/null); terminal=${terminal#TERM_PROGRAM=}
fi
if [ "$(uname)" = Darwin ]; then
 case "$terminal" in
  iTerm.app|iterm2) bundle=com.googlecode.iterm2;; Apple_Terminal|Terminal) bundle=com.apple.Terminal;;
  ghostty|Ghostty) bundle=com.mitchellh.ghostty;; WezTerm|wezterm) bundle=com.github.wez.wezterm;;
  kitty) bundle=net.kovidgoyal.kitty;; Alacritty|alacritty) bundle=org.alacritty;;
  WarpTerminal|Warp) bundle=dev.warp.Warp-Stable;; vscode) bundle=com.microsoft.VSCode;; *) bundle='';;
 esac
 [ -z "$bundle" ] || open -b "$bundle" >/dev/null 2>&1 || :
elif [ -n "${WINDOWID:-}" ] && command -v xdotool >/dev/null 2>&1; then
 xdotool windowactivate "$WINDOWID" >/dev/null 2>&1 || :
fi
