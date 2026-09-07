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
