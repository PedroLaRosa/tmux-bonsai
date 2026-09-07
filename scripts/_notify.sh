#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/_state.sh"

bonsai_terminal() {
  local terminal
  terminal=$(bonsai_opt @bonsai-terminal auto)
  if [ "$terminal" != auto ]; then printf '%s' "$terminal"; return; fi
  terminal=$(tmx display-message -p '#{client_termtype}' 2>/dev/null)
  [ -n "$terminal" ] || terminal=$(tmx show-environment -g TERM_PROGRAM 2>/dev/null)
  case "$terminal" in
    *iTerm*) printf com.googlecode.iterm2;; *Ghostty*|*ghostty*) printf com.mitchellh.ghostty;;
    *WezTerm*|*wezterm*) printf com.github.wez.wezterm;; *kitty*) printf net.kovidgoyal.kitty;;
    *Alacritty*|*alacritty*) printf org.alacritty;; *Warp*) printf dev.warp.Warp-Stable;;
    *vscode*|*Code*) printf com.microsoft.VSCode;; *Apple_Terminal*|*Terminal*) printf com.apple.Terminal;;
  esac
}

bonsai_backends() {
  local backend
  backend=$(bonsai_opt @bonsai-notify-backend auto)
  if [ "$backend" != auto ]; then printf '%s\n' "$backend"; return; fi
  # An SSH host's desktop is not the desktop showing this tmux client.
  if [ -z "${SSH_CONNECTION:-}" ] && [ -z "${SSH_TTY:-}" ]; then
    if [ "$(uname)" = Darwin ]; then
      for backend in terminal-notifier alerter osascript; do
        if command -v "$backend" >/dev/null 2>&1; then printf '%s\n' "$backend"; return; fi
      done
    elif [ -n "${DBUS_SESSION_BUS_ADDRESS:-}${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      for backend in notify-send dunstify gdbus; do
        if command -v "$backend" >/dev/null 2>&1; then printf '%s\n' "$backend"; return; fi
      done
    fi
  fi
  local terminal
  terminal=$(tmx list-clients -F '#{client_termname} #{client_termtype}' 2>/dev/null)
  case "$terminal" in *kitty*|*WezTerm*|*wezterm*|*ghostty*|*Ghostty*|*foot*|*iTerm*) printf 'osc\n';; *) printf 'none\n';; esac
}

bonsai_backend_available() {
  case "$1" in
    none) return 1;;
    osc) bonsai_tmux_at_least 3.3 && [ "$(tmx show-option -gqv allow-passthrough 2>/dev/null)" = all ];;
    command) [ -x "$(bonsai_opt @bonsai-notify-command)" ];;
    terminal-notifier|alerter|osascript|notify-send|dunstify|gdbus) command -v "$1" >/dev/null 2>&1;;
    *) return 1;;
  esac
}

bonsai_verification_current() {
  local file backend part
  file="$(bonsai_state_dir)/notify-verify"
  [ -r "$file" ] || return 1
  backend=$(bonsai_backends)
  jq -e --arg backend "$backend" '.outcome=="verified" and .backend==$backend' "$file" >/dev/null 2>&1 || return 1
  local parts
  IFS=',' read -r -a parts <<< "$backend"
  for part in "${parts[@]}"; do bonsai_backend_available "$part" || return 1; done
  local health
  health="$(bonsai_state_dir)/notify-health-$(bonsai_server_key)"
  [ ! -r "$health" ] || jq -se '.[1].decision!="failed" or .[1].ts<.[0].ts' "$file" "$health" >/dev/null 2>&1
}

bonsai_notify_health() {
  local dir file tmp
  dir=$(bonsai_state_dir); mkdir -p "$dir"
  file="$dir/notify-health-$(bonsai_server_key)"
  tmp=$(mktemp "$dir/.health.XXXXXX") || return
  (umask 077; jq -nc --argjson ts "$(date +%s)" --arg backend "$1" --arg decision "$2" '{ts:$ts,backend:$backend,decision:$decision}' > "$tmp")
  mv "$tmp" "$file"
}

bonsai_notify_id() { bonsai_pane_opt "$1" "@agent_notify_${2//-/_}" 0; }
bonsai_store_notify_id() { tmx set -p -t "$1" "@agent_notify_${2//-/_}" "$3" 2>/dev/null || true; }

bonsai_deliver_backend() {
  local backend=$1 terminal id result seq tty term
  case "$backend" in
    command) "$(bonsai_opt @bonsai-notify-command)";;
    terminal-notifier)
      terminal=$(bonsai_terminal)
      local args=(-title "$BONSAI_TITLE" -subtitle "$BONSAI_SUBTITLE" -message "$BONSAI_BODY" -group "$BONSAI_ID" -execute "$BONSAI_JUMP_CMD")
      [ -z "$terminal" ] || args+=(-activate "$terminal")
      [ -z "$BONSAI_SOUND" ] || args+=(-sound "$BONSAI_SOUND")
      terminal-notifier "${args[@]}";;
    osascript)
      osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv) sound name (item 4 of argv)' -e 'end run' "$BONSAI_TITLE" "$BONSAI_BODY" "$BONSAI_SUBTITLE" "$BONSAI_SOUND";;
    alerter|dunstify)
      bonsai_detach "$BONSAI_SCRIPTS/notify-action.sh" "$backend"; return 3;;
    notify-send)
      if notify-send --help 2>&1 | grep -q -- '--wait'; then
        bonsai_detach "$BONSAI_SCRIPTS/notify-action.sh" notify-send
        return 3
      elif notify-send --help 2>&1 | grep -q -- '--print-id'; then
        id=$(bonsai_notify_id "$BONSAI_PANE" notify-send)
        result=$(notify-send -a bonsai -p -r "$id" -h "string:x-dunst-stack-tag:$BONSAI_ID" -h "string:sound-name:$BONSAI_SOUND" "$BONSAI_TITLE" "$BONSAI_BODY") || return 1
        bonsai_store_notify_id "$BONSAI_PANE" notify-send "$result"
      else notify-send -a bonsai "$BONSAI_TITLE" "$BONSAI_BODY"; fi;;
    gdbus)
      id=$(bonsai_notify_id "$BONSAI_PANE" gdbus)
      result=$(gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify bonsai "$id" dialog-information "$BONSAI_TITLE" "$BONSAI_BODY" '[]' '{}' 8000) || return 1
      id=$(printf '%s' "$result" | sed -n 's/.*uint32 \([0-9][0-9]*\).*/\1/p')
      [ -z "$id" ] || bonsai_store_notify_id "$BONSAI_PANE" gdbus "$id";;
    osc)
      tty=$(tmx display-message -p -t "$BONSAI_PANE" '#{pane_tty}')
      term=$(tmx list-clients -F '#{client_termname} #{client_termtype}')
      # OSC delimiters must never be sourced from user/agent text.
      local title=${BONSAI_TITLE//;/,} body=${BONSAI_BODY//;/,}
      case "$term" in
        *kitty*) printf -v seq '\033]99;i=%s:d=0:p=title:a=focus;%s\033\\\033]99;i=%s:d=1:p=body;%s\033\\' "$BONSAI_ID" "$title" "$BONSAI_ID" "$body";;
        *WezTerm*|*wezterm*|*foot*|*ghostty*|*Ghostty*) printf -v seq '\033]777;notify;%s;%s\a' "$title" "$body";;
        *iTerm*) printf -v seq '\033]9;%s: %s\a' "$title" "$body";;
        *) return 1;;
      esac
      seq=${seq//$'\033'/$'\033\033'}
      [ -w "$tty" ] && printf '\033Ptmux;%s\033\\' "$seq" > "$tty";;
    *) return 1;;
  esac
}

bonsai_dismiss() {
  local pane=$1 backend id
  # Track fan-out independently; never close another application's banners.
  if command -v terminal-notifier >/dev/null 2>&1; then terminal-notifier -remove "bonsai-$pane" >/dev/null 2>&1 || true; fi
  for backend in dunstify gdbus notify-send; do
    id=$(bonsai_notify_id "$pane" "$backend")
    [[ "$id" =~ ^[0-9]+$ ]] && [ "$id" -gt 0 ] || continue
    if [ "$backend" = dunstify ] && command -v dunstify >/dev/null 2>&1; then dunstify -C "$id" >/dev/null 2>&1 || true
    elif command -v gdbus >/dev/null 2>&1; then gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null 2>&1 || true; fi
    bonsai_store_notify_id "$pane" "$backend" 0
  done
}

bonsai_play_sound() {
  local mode=$1 sound=$2 backend=$3 tty
  case "$mode" in bell|both)
    while IFS= read -r tty; do [ ! -w "$tty" ] || printf '\a' > "$tty"; done < <(tmx list-clients -F '#{client_tty}' 2>/dev/null);;
  esac
  [ -n "$sound" ] || return 0
  case "$backend" in *terminal-notifier*|*alerter*|*osascript*|*osc*|*command*|*notify-send*|*dunstify*) return 0;; esac
  if command -v afplay >/dev/null 2>&1 && [ -f "/System/Library/Sounds/$sound.aiff" ]; then bonsai_detach afplay "/System/Library/Sounds/$sound.aiff"
  elif command -v canberra-gtk-play >/dev/null 2>&1; then bonsai_detach canberra-gtk-play -i "$sound"; fi
}
