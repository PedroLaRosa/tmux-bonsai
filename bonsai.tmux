#!/usr/bin/env bash
# tmux-bonsai — git worktrees, agent notifications and a live agent board,
# entirely inside tmux.
#
# Load order for @bonsai-* options (plan §4.2): whatever .tmux.conf already set
# wins, because it is applied before the plugin runs; anything still unset is
# filled from ~/.config/tmux-bonsai/settings.tmux (written by the Notifications
# menu); anything still unset falls back to the built-in defaults below. The
# options that were already present are recorded in @bonsai-pinned so the menu
# can say "(pinned in tmux.conf)" instead of silently losing a toggle on reload.
set -uo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
BONSAI_SCRIPTS="$CURRENT_DIR/scripts"
export BONSAI_SCRIPTS
# shellcheck source=scripts/_lib.sh
. "$BONSAI_SCRIPTS/_lib.sh"

BONSAI_VERSION=0.2.0
HOOK="$BONSAI_SCRIPTS/hooks/tmux-hook.sh"
HOOK_MARKER='hooks/tmux-hook.sh'

# ------------------------------------------------------------------ defaults

# Record what the user pinned in tmux.conf *before* we fill anything in.
pinned=''
for opt in \
  @bonsai-key @bonsai-agent @bonsai-notify @bonsai-notify-finished \
  @bonsai-notify-input @bonsai-notify-error @bonsai-notify-on-bell \
  @bonsai-notify-focus @bonsai-notify-cooldown @bonsai-notify-grace \
  @bonsai-notify-remind @bonsai-notify-preview @bonsai-notify-backend \
  @bonsai-notify-command @bonsai-sound-mode @bonsai-sound-finished \
  @bonsai-sound-input @bonsai-sound-error @bonsai-terminal @bonsai-titlewatch \
  @bonsai-title-settle @bonsai-hooks-tool-events @bonsai-idle-after \
  @bonsai-stale-after @bonsai-glyphs @bonsai-board-refresh @bonsai-board-sort \
  @bonsai-board-show-shells @bonsai-board-window @bonsai-board-side-width \
  @bonsai-board-key @bonsai-next-key @bonsai-status @bonsai-window-glyphs \
  @bonsai-state-dir @bonsai-config-dir
do
  [ -n "$(tmx show-option -gqv "$opt" 2>/dev/null)" ] && pinned="$pinned $opt"
done
tmx set-option -g @bonsai-pinned "${pinned# }" 2>/dev/null

# Then apply the persisted settings file (never touches a pinned option, since
# bonsai_default only fills blanks).
settings_file="$(bs_config_dir)/settings.tmux"
if [ -f "$settings_file" ]; then
  while IFS= read -r line; do
    case "$line" in
      "set -g @bonsai-"*)
        opt=$(printf '%s' "$line" | awk '{print $3}')
        val=$(printf '%s' "$line" | sed -e "s/^set -g $opt //" -e "s/^'//" -e "s/'$//" -e "s/'\\\\''/'/g")
        [ -n "$opt" ] || continue
        [ -n "$(tmx show-option -gqv "$opt" 2>/dev/null)" ] || tmx set-option -g "$opt" "$val" 2>/dev/null
        ;;
    esac
  done < "$settings_file"
fi

bonsai_default() {                                # OPT VALUE
  [ -n "$(tmx show-option -gqv "$1" 2>/dev/null)" ] || tmx set-option -g "$1" "$2" 2>/dev/null
}

bonsai_default @bonsai-key                 W
bonsai_default @bonsai-agent               claude
bonsai_default @bonsai-notify              on
bonsai_default @bonsai-notify-finished     on
bonsai_default @bonsai-notify-input        on
bonsai_default @bonsai-notify-error        on
bonsai_default @bonsai-notify-on-bell      off
bonsai_default @bonsai-notify-focus        strict
bonsai_default @bonsai-notify-cooldown     5
bonsai_default @bonsai-notify-grace        1.5
bonsai_default @bonsai-notify-remind       10m
bonsai_default @bonsai-notify-preview      on
bonsai_default @bonsai-notify-backend      auto
bonsai_default @bonsai-notify-command      ''
bonsai_default @bonsai-sound-mode          system
bonsai_default @bonsai-terminal            auto
bonsai_default @bonsai-titlewatch          on
bonsai_default @bonsai-title-settle        3
bonsai_default @bonsai-hooks-tool-events   on
bonsai_default @bonsai-idle-after          30m
bonsai_default @bonsai-stale-after         6h
bonsai_default @bonsai-glyphs              unicode
bonsai_default @bonsai-board-refresh       2
bonsai_default @bonsai-board-sort          needs-oldest
bonsai_default @bonsai-board-show-shells   off
bonsai_default @bonsai-board-window        bonsai
bonsai_default @bonsai-board-side-width    44
bonsai_default @bonsai-status              off
bonsai_default @bonsai-window-glyphs       off

# Sound defaults differ per platform (macOS system sound names vs freedesktop
# event ids), so they are not a flat constant.
case "$(bs_platform)" in
  darwin)
    bonsai_default @bonsai-sound-finished Glass
    bonsai_default @bonsai-sound-input    Ping
    bonsai_default @bonsai-sound-error    Basso ;;
  *)
    bonsai_default @bonsai-sound-finished message-new-instant
    bonsai_default @bonsai-sound-input    dialog-information
    bonsai_default @bonsai-sound-error    dialog-error ;;
esac

tmx set-option -g @bonsai-version "$BONSAI_VERSION" 2>/dev/null

# ---------------------------------------------------------------- key bindings

key="$(bs_opt @bonsai-key W)"
tmx bind-key "$key" run-shell "$BONSAI_SCRIPTS/menu.sh"

board_key="$(bs_opt @bonsai-board-key '')"
[ -n "$board_key" ] && tmx bind-key "$board_key" run-shell -b "$BONSAI_SCRIPTS/launch.sh board.sh"

next_key="$(bs_opt @bonsai-next-key '')"
[ -n "$next_key" ] && tmx bind-key -n "$next_key" run-shell -b "$BONSAI_SCRIPTS/next.sh"

# -------------------------------------------------------------------- hooks

# Drop our own entries (matched by the marker path, so an install that moved
# from a clone to TPM's directory still gets cleaned up), then append fresh.
# User hooks in the same slot are never touched.
bonsai_unhook() {                                 # HOOK_NAME
  local name="$1" idx
  for idx in $(tmx show-hooks -g "$name" 2>/dev/null | grep -F "$HOOK_MARKER" \
               | sed -n "s/^${name}\[\([0-9]*\)\].*/\1/p" | sort -rn); do
    tmx set-hook -gu "${name}[${idx}]" 2>/dev/null || true
  done
}

bonsai_hook() {                                   # HOOK_NAME COMMAND
  bonsai_unhook "$1"
  tmx set-hook -ga "$1" "$2" 2>/dev/null || true
}

# Acknowledgement. pane-focus-in only fires with an attached client that has
# focus reporting on, so the after-* hooks cover headless and non-reporting
# terminals (verified on 3.4 — see plan Appendix E).
for h in after-select-pane after-select-window client-session-changed client-attached pane-focus-in; do
  bonsai_hook "$h" "run-shell -b '$HOOK ack #{pane_id}'"
done

# Client focus, for `@bonsai-notify-focus strict`.
bonsai_hook client-focus-in  "run-shell -b '$HOOK focus in #{client_tty}'"
bonsai_hook client-focus-out "run-shell -b '$HOOK focus out #{client_tty}'"

# Terminal bell (layer 3).
bonsai_hook alert-bell "run-shell -b '$HOOK bell #{pane_id}'"

# Layer 2: terminal-title evidence. The condition classifies the title inside
# tmux — no fork — and only spawns title.sh when the classification actually
# changed, because spinner frames arrive every ~80 ms.
title_working='#{m/r:(⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|⠋|◐|◓|◑|◒|✦|⏲),#{pane_title}}'
title_idle='#{m/r:(✳|◇|✋),#{pane_title}}'
title_class="#{?${title_working},working,#{?${title_idle},idle,none}}"
bonsai_hook pane-title-changed \
  "if-shell -F '#{&&:#{==:#{@bonsai-titlewatch},on},#{!=:#{@agent_title_state},${title_class}}}' \"run-shell -b '$HOOK title #{pane_id}'\""

# ------------------------------------------------------- status line & glyphs

# The window mirror as a ready-made format. Users add #{E:@bonsai-window-glyph}
# to window-status-format; @bonsai-window-glyphs on injects it for them.
glyph_fmt=''
for st in waiting error working 'done'; do
  glyph_fmt="${glyph_fmt}#{?#{==:#{@agent_window_state},${st}},#[fg=$(bs_color "$st")]$(bs_glyph "$st")#[default] ,}"
done
tmx set-option -g @bonsai-window-glyph "$glyph_fmt"

if bs_is_on "$(bs_opt @bonsai-window-glyphs off)"; then
  for o in window-status-format window-status-current-format; do
    cur=$(tmx show-option -gqv "$o" 2>/dev/null)
    case "$cur" in
      *'@bonsai-window-glyph'*) ;;
      *) [ -n "$cur" ] && tmx set-option -g "$o" "#{E:@bonsai-window-glyph}$cur" 2>/dev/null ;;
    esac
  done
fi

if bs_is_on "$(bs_opt @bonsai-status off)"; then
  cur=$(tmx show-option -gqv status-right 2>/dev/null)
  case "$cur" in
    *'bonsai'*) ;;
    *) tmx set-option -g status-right "#[range=user|bonsai]#($BONSAI_SCRIPTS/status.sh)#[norange]$cur" 2>/dev/null ;;
  esac
  # Clicking the segment opens the board.
  tmx bind-key -T root MouseDown1Status \
    "if-shell -F '#{==:#{mouse_status_range},bonsai}' \
       \"run-shell -b '$BONSAI_SCRIPTS/launch.sh board.sh'\" \
       'select-window -t=' " 2>/dev/null || true
fi

# ------------------------------------------------------------------ first run

state_dir="$(bs_state_dir)"
if [ ! -f "$(bs_config_dir)/settings.tmux" ] && [ ! -f "$state_dir/first-run-shown" ]; then
  mkdir -p "$state_dir" 2>/dev/null && : > "$state_dir/first-run-shown" 2>/dev/null
  tmx display-message "bonsai: prefix+$key → Notifications → setup to enable agent alerts" 2>/dev/null || true
fi

exit 0
