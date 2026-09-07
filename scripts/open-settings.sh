#!/usr/bin/env bash
source "$(dirname "$0")/_notify.sh"
if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
  echo 'Notifications render on the local terminal. Open its notification preferences on your computer.'
  echo 'macOS: open x-apple.systempreferences:com.apple.Notifications-Settings.extension'
  echo 'Windows: explorer.exe ms-settings:notifications'
  exit 0
fi
if [ "$(uname)" = Darwin ]; then
  backend=$(bonsai_backends); bundle=''
  case "$backend" in *terminal-notifier*) bundle=fr.julienxx.terminal-notifier;; *osascript*) bundle=com.apple.ScriptEditor2;; esac
  version=$(sw_vers -productVersion); major=${version%%.*}
  if [ "$major" -ge 13 ]; then open "x-apple.systempreferences:com.apple.Notifications-Settings.extension${bundle:+?id=$bundle}"
  elif [ "$major" -ge 12 ]; then open 'x-apple.systempreferences:com.apple.preference.notifications'
  else open /System/Library/PreferencePanes/Notifications.prefPane; fi
elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe ms-settings:notifications
else
  case "${XDG_CURRENT_DESKTOP:-}" in
    *GNOME*) exec gnome-control-center notifications;;
    *KDE*) if command -v systemsettings >/dev/null 2>&1; then exec systemsettings kcm_notifications; else exec systemsettings5 kcm_notifications; fi;;
    *XFCE*|*Xfce*) exec xfce4-notifyd-config;;
    *Cinnamon*) exec cinnamon-settings notifications;;
    *MATE*) exec mate-notification-properties;;
  esac
  if command -v swaync-client >/dev/null 2>&1; then swaync-client -t
  elif command -v dunstctl >/dev/null 2>&1; then echo "Edit ${XDG_CONFIG_HOME:-$HOME/.config}/dunst/dunstrc; dunstctl set-paused false disables Do Not Disturb."
  elif command -v makoctl >/dev/null 2>&1; then echo "Edit ${XDG_CONFIG_HOME:-$HOME/.config}/mako/config; makoctl mode -r do-not-disturb disables Do Not Disturb."
  else echo 'Open your desktop notification preferences and allow banners from bonsai. Run bonsai doctor for backend details.'; fi
fi
