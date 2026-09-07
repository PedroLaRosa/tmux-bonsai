#!/usr/bin/env bash
source "$(dirname "$0")/_notify.sh"
pane=${TMUX_PANE:-$(tmx display -p '#{pane_id}')}
while :; do
  backend=$(bonsai_backends)
  accepted=no
  "$BONSAI_SCRIPTS/notify.sh" deliver "$pane" test --test && accepted=yes
  printf '\nBackend: %s · accepted: %s\n' "$backend" "$accepted"
  echo 'A backend accepting a request does not prove a banner appeared.'
  printf 'Did a banner appear? [y/n] '
  IFS= read -r answer || wt_back
  case "$answer" in y|Y) outcome=verified;; *) outcome=not-displayed;; esac
  [ "$accepted" = yes ] || outcome=not-sent
  dir=$(bonsai_state_dir); mkdir -p "$dir"
  (umask 077; jq -nc --argjson ts "$(date +%s)" --arg backend "$backend" --arg outcome "$outcome" '{ts:$ts,backend:$backend,outcome:$outcome}' > "$dir/notify-verify")
  [ "$outcome" != verified ] || { printf 'Verified. Press Enter to return. '; read -r _; wt_back; }
  case "$backend" in
    *terminal-notifier*) echo 'Allow banners and sounds for terminal-notifier in System Settings → Notifications.';;
    *osascript*) echo 'Allow banners and sounds for Script Editor in System Settings → Notifications.';;
    *osc*) echo 'Enable notifications in your local terminal; tmux needs allow-passthrough all.';;
    *) echo 'Check your notification daemon, banner permissions, and Do Not Disturb.';;
  esac
  printf '[o] open settings · [b] backend · [r] retry · [Enter] back: '
  IFS= read -r action || wt_back
  case "$action" in
    o) "$BONSAI_SCRIPTS/open-settings.sh";;
    b) printf 'Backend (auto/terminal-notifier/osascript/notify-send/osc/command): '; read -r value; "$BONSAI_SCRIPTS/settings.sh" set notify-backend "$value";;
    r) ;;
    *) wt_back;;
  esac
done
