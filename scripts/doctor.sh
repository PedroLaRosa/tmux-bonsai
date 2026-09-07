#!/usr/bin/env bash
source "$(dirname "$0")/_notify.sh"
if ! command -v jq >/dev/null 2>&1; then
  if [ "${1:-}" = --json ]; then printf '%s\n' '[{"name":"jq","status":"missing","detail":"not found","fix":"Install jq, then rerun bonsai doctor."}]'
  else echo '✗ jq: not found. Install jq, then rerun bonsai doctor.'; fi
  exit 1
fi
json=false; [ "${1:-}" != --json ] || json=true
records='[]'
check() {
  records=$(printf '%s' "$records" | jq -c --arg name "$1" --arg status "$2" --arg detail "$3" --arg fix "${4:-}" '.+[{name:$name,status:$status,detail:$detail,fix:$fix}]')
}
for dependency in tmux jq fzf curl git wt; do
  path=$(command -v "$dependency" 2>/dev/null)
  if [ -n "$path" ]; then check "$dependency" ok "$path"; else check "$dependency" missing 'not found' "Install $dependency and ensure it is on the tmux server PATH."; fi
done
version=$(tmx -V 2>/dev/null)
if bonsai_tmux_at_least 3.3; then check tmux-features ok "$version: popups, titles and passthrough supported"
elif bonsai_tmux_at_least 3.2; then check tmux-features warning "$version: basic popups only" 'Upgrade to 3.3+ for titles and OSC.'
else check tmux-features missing "$version" 'Install tmux 3.2 or later.'; fi
fzf_version=$(fzf --version 2>/dev/null)
if printf '%s' "$fzf_version" | awk -F. '{exit !(($1+0)>0 || ($2+0)>=40)}'; then check fzf-features ok "$fzf_version: live refresh and cursor tracking"
else check fzf-features warning "$fzf_version" 'Upgrade fzf to 0.40 or later for live refresh; older versions use Ctrl-R to reload.'; fi
check terminal ok "${TERM_PROGRAM:-unknown} / $(bonsai_terminal)"
focus=$(tmx show-option -gqv focus-events 2>/dev/null)
if [ "$focus" = on ] && [ -s "$(bonsai_focus_file)" ]; then check focus ok 'focus reporting observed'
else check focus warning "focus-events=$focus; no currently focused client recorded" 'Enable focus-events and focus the terminal, or choose notify-focus attached.'; fi
check passthrough info "$(tmx show-option -gqv allow-passthrough 2>/dev/null)" 'OSC requires tmux 3.3+ and allow-passthrough all.'
backends=$(bonsai_backends); IFS=',' read -r -a backend_list <<< "$backends"
for backend in "${backend_list[@]}"; do
  if bonsai_backend_available "$backend"; then check backend ok "$backend available (display unverified)"
  else check backend warning "$backend unavailable" 'Install a backend or select a command/OSC backend.'; fi
done
if command -v gdbus >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  daemon=$(gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetServerInformation 2>/dev/null)
  check daemon info "${daemon:-no daemon response}"
fi
if command -v dunstctl >/dev/null 2>&1; then check DND info "dunst paused: $(dunstctl is-paused 2>/dev/null)"
elif command -v makoctl >/dev/null 2>&1; then check DND info "mako modes: $(makoctl mode 2>/dev/null)"
elif command -v gsettings >/dev/null 2>&1; then check DND info "GNOME show-banners: $(gsettings get org.gnome.desktop.notifications show-banners 2>/dev/null)"; fi
if [ "$(uname)" = Darwin ] && [ -r "$HOME/Library/DoNotDisturb/DB/Assertions.json" ]; then
  dnd=$(plutil -convert json -o - "$HOME/Library/DoNotDisturb/DB/Assertions.json" 2>/dev/null | jq -r 'if (.data[0].storeAssertionRecords // .storeAssertionRecords // [] | length)>0 then "Focus may be active" else "no Focus assertion observed" end')
  check DND info "${dnd:-permission unavailable}"
fi
for agent in claude opencode codex gemini cursor copilot droid; do
  [ ! -x "$BONSAI_SCRIPTS/adapters/$agent.sh" ] || check "hooks-$agent" info "$("$BONSAI_SCRIPTS/adapters/$agent.sh" status 2>/dev/null)" 'Run bonsai hooks install for repairs.'
done
file="$(bonsai_state_dir)/notify-verify"
if [ -r "$file" ]; then check verification info "$(cat "$file")"; else check verification warning 'never tested' 'Run bonsai notify test.'; fi
log="$(bonsai_state_dir)/events.jsonl"; size=0; [ ! -f "$log" ] || size=$(wc -c < "$log")
check events info "$log ($size bytes)"
check PATH info "$PATH"
if tmx show-hooks -g 2>/dev/null | grep -q tmux-agent-notify || { [ -r "$HOME/.claude/settings.json" ] && grep -q tmux-agent-notify "$HOME/.claude/settings.json"; }; then
  check companion warning 'tmux-agent-notify hooks detected' 'Remove the companion plugin and its managed hooks after enabling bonsai.'
fi
if "$json"; then printf '%s\n' "$records"; else
  printf '%s' "$records" | jq -r '.[] | (if .status=="ok" then "✓" elif .status=="missing" then "✗" elif .status=="warning" then "⚠" else "·" end)+" "+.name+": "+.detail+(if .fix!="" then "\n  "+.fix else "" end)'
fi
