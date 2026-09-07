#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
setup_test
# Shell and tmux quoting are separate layers. Exercise spaces, apostrophes,
# double quotes and shell metacharacters without ever evaluating user data.
plugin="$TMP/plugin 'quoted' \"double\" \$literal"
mkdir -p "$plugin"
cp -R "$TEST_ROOT/scripts" "$plugin/"
cp "$TEST_ROOT/bonsai.tmux" "$plugin/"
bash "$plugin/bonsai.tmux"
assert_contains "$(tmx show-hooks -g)" tmux-hook.sh
assert_contains "$(tmx show-hooks -gw)" pane-title-changed
mkdir -p "$TMP/bin"
ln -s "$plugin/scripts/bonsai" "$TMP/bin/bonsai"
assert_contains "$("$TMP/bin/bonsai" help)" 'Usage: bonsai'
record="$TMP/result"
probe="$plugin/probe.sh"
cat > "$probe" <<'PROBE'
#!/usr/bin/env bash
printf '%s' "$2" > "$1"
PROBE
chmod +x "$probe"
value='literal $(touch ignored); "quote" and '\''apostrophe'
command=$(bonsai_run_command "$probe" "$record" "$value")
printf '%s\n' "$command" | tmx source-file -
assert_eq "$value" "$(cat "$record")"
"$BONSAI_SCRIPTS/settings.sh" set notify-command "$probe"
"$BONSAI_SCRIPTS/settings.sh" init
assert_eq "$probe" "$(bonsai_opt @bonsai-notify-command)"
literal='$literal ${name} $(command) \$escaped \\$twice $9 \037'
"$BONSAI_SCRIPTS/settings.sh" set sound-input "$literal"
"$BONSAI_SCRIPTS/settings.sh" init
assert_eq "$literal" "$(bonsai_opt @bonsai-sound-input)"
assert_jq "$(tmx show-option -gqv @bonsai-applied)" '.["@bonsai-sound-input"] == "$literal ${name} $(command) \\$escaped \\\\$twice $9 \\037"'
# Split inherits the selected pane's literal path and honors BONSAI_SOCKET even
# when the caller's TMUX points elsewhere.
window=$(tmx new-window -P -F '#{window_id}' -c "$plugin" 'sleep 3600')
tmx select-window -t "$window"
tmx set-option -g @bonsai-agent ':'
TMUX="$TMP/missing.sock,0,0" bash "$BONSAI_SCRIPTS/split.sh" -h
assert_eq "$(cd "$plugin" && pwd -P)" "$(tmx display-message -p '#{pane_current_path}')"
assert_eq 2 "$(tmx list-panes -t "$window" -F '#{pane_id}' | wc -l | tr -d ' ')"
# Terminal capture bypasses tmux's formatted output quoting, so the raw path
# must preserve literal backslashes before both ASCII and Unicode dollars.
capture_pane=$(tmx new-window -d -P -F '#{pane_id}' 'cat')
capture_text='literal \$name \$é $é ${name} \037'
tmx send-keys -t "$capture_pane" -l -- "$capture_text"
tmx send-keys -t "$capture_pane" Enter
sleep 0.1
assert_contains "$("$BONSAI_SCRIPTS/capture.sh" "$capture_pane")" "$capture_text"
