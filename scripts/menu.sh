#!/usr/bin/env bash
S="$(cd "$(dirname "$0")" && pwd)"
source "$S/_lib.sh"
run() { bonsai_run_command -b "$@"; }
popup() { run "$S/launch.sh" "$@"; }
counts=$("$S/status.sh" 2>/dev/null)

# tmux draws nothing at all when a menu is taller than the client, so a short
# terminal silently gets no menu. Section titles stay in every case; the blank
# separator rows are what gets dropped to make it fit.
# ponytail: separators are the only expendable rows, so below ~28 lines even the
# compact menu overflows and tmux goes silent again.
menu=() rows=0 compact=off
sec()  { menu+=("-#[align=centre]$1" '' ''); rows=$((rows+1)); }
gap()  { [ "$compact" = on ] || { menu+=(''); rows=$((rows+1)); }; }
item() { menu+=("$1" "$2" "$3"); rows=$((rows+1)); }

build() {
  menu=() rows=0
  sec 'Session'
  item 'new session worktree'            n   "$(popup new.sh)"
  item 'new session worktree + agent'    a   "$(popup new.sh agent)"
  item 'open / switch session worktree'  o   "$(popup switch.sh)"
  gap
  sec 'Window'
  item 'new window worktree'             w   "$(popup window.sh)"
  item 'new window worktree + agent'     W   "$(popup window.sh agent)"
  item 'open / switch window worktree'   O   "$(popup window-switch.sh)"
  item 'promote window->session'         r   "$(run "$S/promote.sh")"
  gap
  sec 'Pane'
  item 'split pane right + agent'        '|' "$(run "$S/split.sh" -h)"
  item 'split pane down + agent'         _   "$(run "$S/split.sh" -v)"
  gap
  sec "Agents $counts"
  item 'agent board (popup)'             d   "$(popup board.sh)"
  item 'agent board as window'           D   "$(run "$S/board.sh" --window)"
  item 'agent board as side pane'        B   "$(run "$S/board.sh" --side)"
  item 'jump to next needs-you'          j   "$(run "$S/next.sh")"
  item 'back to previous session'        J   'switch-client -l'
  item 'activity feed'                   f   "$(popup feed.sh)"
  item 'mark current pane unread'        u   "$(run "$S/bonsai" unread '#{pane_id}')"
  gap
  sec 'Notifications #{@bonsai-notify}'
  item 'notification settings…'          N   "$(run "$S/notify-menu.sh")"
  gap
  sec 'Worktrees'
  item 'list worktrees'                  L   "$(popup worktrees.sh)"
  gap
  sec 'Remove'
  item 'remove current worktree'         x   "confirm-before -p 'remove this worktree? (y/n)' $(bonsai_tmux_quote "$(run "$S/remove.sh")")"
}

build
# the menu box adds a border row above (carrying the title) and below the items
height=$(tmx display -p '#{client_height}' 2>/dev/null)
case "$height" in ''|*[!0-9]*) height=0;; esac
if [ "$height" -lt $((rows + 3)) ]; then compact=on; build; fi

tmx display-menu -T '#[align=centre] bonsai ' -- "${menu[@]}"
