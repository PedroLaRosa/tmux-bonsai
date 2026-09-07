#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"
# A fixed schema keeps persisted values data, even when they contain quotes.
defaults() {
  local finished=Glass input=Ping error=Basso
  [ "$(uname)" = Darwin ] || { finished=message-new-instant; input=dialog-information; error=dialog-error; }
  cat <<VALUES
notify|on
notify-finished|on
notify-input|on
notify-error|on
notify-on-bell|off
notify-focus|strict
notify-cooldown|5
notify-grace|1.5
notify-remind|10m
notify-preview|on
notify-backend|auto
notify-command|
sound-mode|system
sound-finished|$finished
sound-input|$input
sound-error|$error
terminal|auto
titlewatch|on
title-settle|3
hooks-tool-events|on
idle-after|30m
stale-after|6h
glyphs|unicode
board-refresh|2
board-sort|needs-oldest
board-show-shells|off
board-window|bonsai
board-side-width|44
board-key|
next-key|
status|off
window-glyphs|off
VALUES
}
normalize() { case "$1" in @bonsai-*) printf '%s' "$1";; *) printf '@bonsai-%s' "$1";; esac; }
validate() {
  local key=${1#@bonsai-} value=$2
  case "$value" in *$'\n'*|*$'\r'*) return 1;; esac
  case "$key" in
    notify|notify-finished|notify-input|notify-error|notify-on-bell|notify-preview|titlewatch|hooks-tool-events|board-show-shells|status|window-glyphs) [[ "$value" = on || "$value" = off ]];;
    notify-focus) [[ "$value" = strict || "$value" = attached || "$value" = off ]];;
    sound-mode) [[ "$value" = system || "$value" = bell || "$value" = both || "$value" = off ]];;
    glyphs) [[ "$value" = unicode || "$value" = emoji || "$value" = ascii ]];;
    board-sort) [[ "$value" = needs-oldest || "$value" = recent ]];;
    notify-cooldown|notify-grace|title-settle|idle-after|stale-after) bonsai_duration "$value" >/dev/null;;
    board-refresh) bonsai_duration "$value" | awk '{exit !($1 > 0)}';;
    notify-remind) [ "$value" = off ] || bonsai_duration "$value" >/dev/null;;
    board-side-width) [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 20 ];;
    notify-backend) [[ "$value" =~ ^(auto|terminal-notifier|alerter|osascript|notify-send|dunstify|gdbus|osc|command|none)(,(terminal-notifier|alerter|osascript|notify-send|dunstify|gdbus|osc|command|none))*$ ]];;
    notify-command|sound-finished|sound-input|sound-error|terminal|board-window|board-key|next-key|state-dir|config-dir) return 0;;
    *) return 1;;
  esac
}
# tmux double-quoted string escaping (not shell escaping).
quote_tmux() {
  local value=$1
  value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//\$/\\\$}; value=${value//\`/\\\`}
  printf '"%s"' "$value"
}
persist() {
  local option=$1 value=$2 mode=${3:-set} dir file tmp
  dir=$(bonsai_config_dir); mkdir -p "$dir"
  file=$dir/settings.tmux
  tmx wait-for -L bonsai-settings
  trap 'tmx wait-for -U bonsai-settings 2>/dev/null || true' EXIT
  tmp=$(mktemp "$dir/.settings.XXXXXX"); chmod 600 "$tmp"
  if [ -f "$file" ]; then awk -v key="$option" '$3!=key' "$file" > "$tmp"; fi
  if [ "$mode" = set ]; then printf 'set -g %s %s\n' "$option" "$(quote_tmux "$value")" >> "$tmp"; fi
  mv "$tmp" "$file"
  tmx wait-for -U bonsai-settings; trap - EXIT
}
case "${1:-list}" in
  defaults) defaults;;
  init)
    pinned=$(tmx show-option -gqv @bonsai-pinned)
    if [ "$(tmx show-option -gqv @bonsai-initialized)" != 1 ]; then
      pinned=$(tmx show-options -g | awk '$1 ~ /^@bonsai-/ {printf "%s ",$1}')
      tmx set -g @bonsai-pinned "$pinned" \; set -g @bonsai-initialized 1
    fi
    file="$(bonsai_config_dir)/settings.tmux"
    if [ -f "$file" ]; then
      tmp=$(mktemp "${TMPDIR:-/tmp}/bonsai-settings.XXXXXX")
      awk -v pinned=" $pinned " '$1=="set" && $2=="-g" && $3 ~ /^@bonsai-/ && !index(pinned," "$3" ")' "$file" > "$tmp"
      tmx source-file "$tmp"; rm -f "$tmp"
    fi
    while IFS='|' read -r key value; do
      current=$(tmx show-option -gqv "@bonsai-$key")
      [ -n "$current" ] || tmx set -g "@bonsai-$key" "$value"
    done < <(defaults)
    ;;
  list)
    tmx show-options -g | awk '$1 ~ /^@bonsai-/';;
  get) bonsai_opt "$(normalize "${2:?setting required}")"; printf '\n';;
  set)
    option=$(normalize "${2:?setting required}"); value=${3:?value required}
    validate "$option" "$value" || { echo "Invalid setting/value: $option" >&2; exit 2; }
    persist "$option" "$value"; tmx set -g "$option" "$value"
    tmx refresh-client -S 2>/dev/null || true
    ;;
  reset)
    option=$(normalize "${2:?setting required}")
    value=$(defaults | awk -F '|' -v key="${option#@bonsai-}" '$1==key {print $2; found=1} END {exit !found}')
    persist "$option" '' reset; tmx set -g "$option" "$value";;
  *) echo 'Usage: bonsai settings get|set|list|reset [name] [value]' >&2; exit 2;;
esac
