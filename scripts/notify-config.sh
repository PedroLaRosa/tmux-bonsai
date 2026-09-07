#!/usr/bin/env bash
source "$(dirname "$0")/_lib.sh"
case "${1:-}" in
  sound-finished|sound-input|sound-error|notify-command)
    printf '%s: ' "$1"; IFS= read -r value || wt_back
    [ -z "$value" ] || "$BONSAI_SCRIPTS/settings.sh" set "$1" "$value";;
  doctor) "$BONSAI_SCRIPTS/doctor.sh"; printf '\nPress Enter to return. '; read -r _;;
  open-settings) "$BONSAI_SCRIPTS/open-settings.sh"; printf '\nPress Enter to return. '; read -r _;;
esac
wt_back
