#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"
S=$BONSAI_SCRIPTS
run() { bonsai_run_command -b "$@"; }
popup() { run "$S/launch.sh" "$@"; }
case "${1:-}" in
  set) "$S/settings.sh" set "$2" "${3:-}";;
  toggle)
    key=$2; value=$(bonsai_opt "@bonsai-$key" off)
    [ "$value" != on ] && value=on || value=off
    "$S/settings.sh" set "$key" "$value";;
  focus)
    case "$(bonsai_opt @bonsai-notify-focus strict)" in strict) value=attached;; attached) value=off;; *) value=strict;; esac
    "$S/settings.sh" set notify-focus "$value";;
  remind)
    value=$(bonsai_opt @bonsai-notify-remind 10m)
    [ "$value" != off ] && value=off || value=10m
    "$S/settings.sh" set notify-remind "$value";;
  clear) "$S/clear-markers.sh" all;;
  backend)
    options=(); index=0
    for backend in auto terminal-notifier alerter osascript notify-send dunstify gdbus osc command none; do
      options+=( "$backend" "$index" "$(run "$S/notify-menu.sh" set notify-backend "$backend")" ); index=$((index+1))
    done
    options+=( 'set command path…' c "$(popup notify-config.sh notify-command)" )
    tmx display-menu -T ' notification backend ' -- "${options[@]}" '← back' Escape "$(run "$S/notify-menu.sh")"
    exit;;
  sound)
    tmx display-menu -T ' notification sounds ' -- \
      'finished sound…' f "$(popup notify-config.sh sound-finished)" \
      'input sound…' i "$(popup notify-config.sh sound-input)" \
      'error sound…' e "$(popup notify-config.sh sound-error)" \
      'system' s "$(run "$S/notify-menu.sh" set sound-mode system)" \
      'terminal bell' b "$(run "$S/notify-menu.sh" set sound-mode bell)" \
      'both' B "$(run "$S/notify-menu.sh" set sound-mode both)" \
      'off' o "$(run "$S/notify-menu.sh" set sound-mode off)" \
      '← back' Escape "$(run "$S/notify-menu.sh")"
    exit;;
esac
pinned=$(bonsai_opt @bonsai-pinned)
label() {
  local option=$1 text=$2 suffix=''
  case " $pinned " in *" @bonsai-$option "*) suffix=' (pinned in tmux.conf)';; esac
  printf '%s' "$text$suffix"
}
evidence='never tested'
if [ -r "$(bonsai_state_dir)/notify-verify" ]; then evidence=$(jq -r .outcome "$(bonsai_state_dir)/notify-verify" 2>/dev/null); fi
tmx display-menu -T ' notifications ' -- \
  "$(label notify '[#{?#{==:#{@bonsai-notify},on},x, }] notifications')" e "$(run "$S/notify-menu.sh" toggle notify)" \
  "$(label notify-finished '[#{?#{==:#{@bonsai-notify-finished},on},x, }] agent finished')" 1 "$(run "$S/notify-menu.sh" toggle notify-finished)" \
  "$(label notify-input '[#{?#{==:#{@bonsai-notify-input},on},x, }] agent needs input')" 2 "$(run "$S/notify-menu.sh" toggle notify-input)" \
  "$(label notify-error '[#{?#{==:#{@bonsai-notify-error},on},x, }] agent error')" 3 "$(run "$S/notify-menu.sh" toggle notify-error)" \
  "$(label notify-on-bell '[#{?#{==:#{@bonsai-notify-on-bell},on},x, }] terminal bell')" 4 "$(run "$S/notify-menu.sh" toggle notify-on-bell)" \
  "$(label notify-focus 'suppress while focused: #{@bonsai-notify-focus}')" s "$(run "$S/notify-menu.sh" focus)" \
  'sound: #{@bonsai-sound-mode}' S "$(run "$S/notify-menu.sh" sound)" \
  'reminder: #{@bonsai-notify-remind}' m "$(run "$S/notify-menu.sh" remind)" \
  'backend: #{@bonsai-notify-backend}' b "$(run "$S/notify-menu.sh" backend)" \
  "-$evidence" '' '' \
  'send test notification' t "$(popup notify-test.sh)" \
  'open system notification settings' o "$(popup notify-config.sh open-settings)" \
  'setup / repair agent hooks…' h "$(popup notify-setup.sh)" \
  'doctor' D "$(popup notify-config.sh doctor)" \
  'clear all agent markers' c "confirm-before -p 'Clear all agent markers? (y/n)' $(bonsai_tmux_quote "$(run "$S/notify-menu.sh" clear)")" \
  '← back' Escape "$(run "$S/menu.sh")"
