#!/usr/bin/env bash
# Worktrees, agent state, notifications, and a live tmux-native board.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$CURRENT_DIR/scripts/_lib.sh"
"$BONSAI_SCRIPTS/settings.sh" init
export BONSAI_SOCKET="${BONSAI_SOCKET:-${TMUX:-}}"; BONSAI_SOCKET=${BONSAI_SOCKET%%,*}
[ -n "$BONSAI_SOCKET" ] || BONSAI_SOCKET=$(tmx display -p '#{socket_path}')
tmx set -g @bonsai-version 1.0
key=$(bonsai_opt @bonsai-key W)
tmx bind-key "$key" run-shell "$(bonsai_shell_quote "$BONSAI_SCRIPTS/menu.sh")"
# Remove only this plugin's hook entries, preserving both user hooks and indexes.
while IFS= read -r line; do
  case "$line" in *'/tmux-hook.sh'*) tmx set-hook -gu "${line%% *}" 2>/dev/null || true;; esac
done < <( { tmx show-hooks -g; tmx show-hooks -gw; } 2>/dev/null)
register_hook() {
  local hook=$1 event=$2 command
  command="$(bonsai_shell_quote "$BONSAI_SCRIPTS/tmux-hook.sh") $event '#{pane_id}' '#{client_tty}' '#{window_id}'"
  command="BONSAI_SOCKET=$(bonsai_shell_quote "$BONSAI_SOCKET") $command"
  tmx set-hook -ga "$hook" "run-shell -b $(bonsai_tmux_quote "$command")" 2>/dev/null || true
}
for hook in after-select-pane after-select-window client-session-changed client-attached pane-focus-in; do register_hook "$hook" ack; done
register_hook client-focus-in focus-in
register_hook client-focus-out focus-out
register_hook client-detached detach
register_hook alert-bell bell
register_hook alert-silence silence
register_hook pane-exited exit
register_hook after-kill-pane exit
# This classification runs in tmux so spinner frames of the same state never fork.
class=$("$BONSAI_SCRIPTS/title.sh" --format)
command="BONSAI_SOCKET=$(bonsai_shell_quote "$BONSAI_SOCKET") $(bonsai_shell_quote "$BONSAI_SCRIPTS/tmux-hook.sh") title '#{pane_id}'"
condition="#{&&:#{==:#{@bonsai-titlewatch},on},#{!=:#{@agent_title_state},$class}}"
tmx set-hook -ga pane-title-changed "if-shell -F $(bonsai_tmux_quote "$condition") $(bonsai_tmux_quote "run-shell -b $(bonsai_tmux_quote "$command")")" 2>/dev/null || true
board_key=$(bonsai_opt @bonsai-board-key)
[ -z "$board_key" ] || tmx bind-key "$board_key" run-shell -b "$(bonsai_shell_quote "$BONSAI_SCRIPTS/launch.sh") board.sh"
next_key=$(bonsai_opt @bonsai-next-key)
[ -z "$next_key" ] || tmx bind-key -n "$next_key" run-shell -b "$(bonsai_shell_quote "$BONSAI_SCRIPTS/next.sh")"
glyph="#{?#{==:#{@agent_state},waiting},#[fg=colour214]$(bonsai_glyph waiting) ,#{?#{==:#{@agent_state},error},#[fg=colour196]$(bonsai_glyph error) ,#{?#{==:#{@agent_state},working},#[fg=colour39]$(bonsai_glyph working) ,#{?#{==:#{@agent_state},done},#[fg=colour78]$(bonsai_glyph 'done') ,}}}}#[default]"
tmx set -g @bonsai-window-glyph "$glyph"
if [ "$(bonsai_opt @bonsai-window-glyphs off)" = on ]; then
  for option in window-status-format window-status-current-format; do
    current=$(tmx show-option -gqv "$option")
    case "$current" in *'#{E:@bonsai-window-glyph}'*) ;; *) tmx set -g "$option" "#{E:@bonsai-window-glyph}$current";; esac
  done
fi
if [ "$(bonsai_opt @bonsai-status off)" = on ]; then
  current=$(tmx show-option -gqv status-right)
  case "$current" in *'/status.sh'*) ;; *) tmx set -g status-right "#($(bonsai_shell_quote "$BONSAI_SCRIPTS/status.sh")) $current";; esac
  # Save the existing mouse action once so clicks outside our range retain it.
  if [ -z "$(tmx show-option -gqv @bonsai-mouse-original)" ]; then
    original=$(tmx list-keys -T root MouseDown1Status 2>/dev/null | sed 's/^.*MouseDown1Status[[:space:]]*//')
    tmx set -g @bonsai-mouse-original "${original:-select-window -t =}"
  fi
  original=$(tmx show-option -gqv @bonsai-mouse-original)
  tmx bind -T root MouseDown1Status if -F '#{==:#{mouse_status_range},bonsai}' "$(bonsai_run_command -b "$BONSAI_SCRIPTS/launch.sh" board.sh)" "$original"
fi
state_dir=$(bonsai_state_dir); config_dir=$(bonsai_config_dir)
if [ ! -e "$state_dir/first-run-shown" ] && [ ! -f "$config_dir/settings.tmux" ]; then
  (umask 077; mkdir -p "$state_dir"; touch "$state_dir/first-run-shown")
  tmx display-message 'bonsai: prefix+W → Notifications → setup to enable agent alerts' 2>/dev/null || true
fi
