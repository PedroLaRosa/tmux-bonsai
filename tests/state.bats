#!/usr/bin/env bats
# _lib.sh / _state.sh — the foundation every other script builds on.

load helper

setup_file() { bonsai_setup_server; }
teardown_file() { bonsai_teardown_server; }

setup() {
  # shellcheck source=scripts/_state.sh
  . "$BONSAI_SCRIPTS/_state.sh"
  PANE="$(new_pane)"
}

teardown() { t kill-pane -t "$PANE" 2>/dev/null || true; }

@test "durations parse seconds, fractions and suffixes" {
  [ "$(bs_dur 5)"    = 5 ]
  [ "$(bs_dur 1.5)"  = 1.5 ]
  [ "$(bs_dur 30s)"  = 30 ]
  [ "$(bs_dur 10m)"  = 600 ]
  [ "$(bs_dur 2h)"   = 7200 ]
  [ -z "$(bs_dur off)" ]
  [ -z "$(bs_dur '')" ]
  [ "$(bs_dur_i 1.5)" = 2 ]
  [ "$(bs_dur_i 10m)" = 600 ]
}

@test "age formatting switches unit at each boundary" {
  [ "$(bs_age_fmt 41)"    = "41s" ]
  [ "$(bs_age_fmt 720)"   = "12m" ]
  [ "$(bs_age_fmt 10800)" = "3h"  ]
  [ "$(bs_age_fmt 172800)" = "2d" ]
}

@test "version comparison handles tmux's trailing letter" {
  bs_version_ge 3.4 3.3
  bs_version_ge 3.3a 3.3
  bs_version_ge 3.3 3.3
  ! bs_version_ge 3.2 3.3
  ! bs_version_ge 2.9 3.0
}

@test "sanitize strips control characters and collapses whitespace" {
  run bs_sanitize "$(printf 'a\tb\nc\037d  e')"
  [ "$output" = "a b c d e" ]
}

@test "truncate cuts on character boundaries, not bytes" {
  run bs_trunc "ααααααααα" 5
  [ "${#output}" -eq 5 ]
  run bs_trunc "abc" 10
  [ "$output" = "abc" ]
}

@test "severity orders waiting above error above working" {
  [ "$(bs_severity waiting)" -gt "$(bs_severity error)" ]
  [ "$(bs_severity error)"   -gt "$(bs_severity working)" ]
  [ "$(bs_severity working)" -gt "$(bs_severity done)" ]
  [ "$(bs_severity done)"    -gt "$(bs_severity idle)" ]
  [ "$(bs_severity idle)"    -gt "$(bs_severity unknown)" ]
}

@test "glyph sets are complete and single-width by default" {
  [ "$(bs_glyph waiting unicode)" = "●" ]
  [ "$(bs_glyph waiting ascii)"   = "[!]" ]
  [ "$(bs_glyph waiting emoji)"   = "💬" ]
  [ -n "$(bs_glyph nonsense unicode)" ]
}

@test "state round-trips through pane options" {
  st_write "$PANE" @agent_state waiting @agent_state_ts 1700000000 @agent_ask 'Bash: npm test'
  st_load "$PANE"
  [ "$ST_state" = waiting ]
  [ "$ST_state_ts" = 1700000000 ]
  [ "$ST_ask" = 'Bash: npm test' ]
  [ -n "$ST_session_name" ]
}

@test "non-ASCII survives a round trip" {
  st_write "$PANE" @agent_msg 'héllo ✔ ● — dashed'
  st_load "$PANE"
  [ "$ST_msg" = 'héllo ✔ ● — dashed' ]
}

@test "a value containing the escaped separator does not shift fields" {
  # tmux renders a real 0x1F as the four characters \037 and does not escape a
  # backslash, so this text is indistinguishable from a separator on the fast
  # path. st_load must notice the field count and re-read field by field.
  st_write "$PANE" @agent_msg 'literal \037 here' @agent_state done @agent_ask 'after'
  st_load "$PANE"
  [ "$ST_msg" = 'literal \037 here' ]
  [ "$ST_state" = done ]
  [ "$ST_ask" = 'after' ]
}

@test "a value that is exactly a semicolon does not break the chained write" {
  st_write "$PANE" @agent_ask ';' @agent_state waiting
  st_load "$PANE"
  [ "$ST_state" = waiting ]
  [ -n "$ST_ask" ]
}

@test "empty values clear a field without shifting the rest" {
  st_write "$PANE" @agent_msg 'something' @agent_ask 'q'
  st_write "$PANE" @agent_msg '' @agent_tool ''
  st_load "$PANE"
  [ -z "$ST_msg" ]
  [ -z "$ST_tool" ]
  [ "$ST_ask" = 'q' ]
}

@test "defaults fill in for a pane that has never seen an agent" {
  st_load "$PANE"
  [ "$ST_state" = unknown ]
  [ "$ST_state_ts" = 0 ]
  [ "$ST_seq" = 0 ]
}

@test "non-numeric numeric fields are coerced to zero" {
  st_write "$PANE" @agent_state_ts 'garbage' @agent_seq 'x'
  st_load "$PANE"
  [ "$ST_state_ts" = 0 ]
  [ "$ST_seq" = 0 ]
}

@test "window mirror takes the most severe pane state" {
  local w p2
  w=$(t display-message -p -t "$PANE" '#{window_id}')
  p2=$(t split-window -t "$PANE" -P -F '#{pane_id}' -d)
  st_write "$PANE" @agent_state done
  st_write "$p2"   @agent_state waiting
  st_mirror_window "$PANE"
  [ "$(t display-message -p -t "$w" '#{@agent_window_state}')" = waiting ]
  st_write "$p2" @agent_state working
  st_mirror_window "$PANE"
  [ "$(t display-message -p -t "$w" '#{@agent_window_state}')" = working ]
}

@test "the window mirror is not shadowed by the active pane's own state" {
  # tmux resolves @foo pane-first even for a window target, so the mirror must
  # live under a name no pane uses; otherwise window-status-format silently
  # renders the active pane instead of the most severe one.
  local w p2
  w=$(t display-message -p -t "$PANE" '#{window_id}')
  p2=$(t split-window -t "$PANE" -P -F '#{pane_id}' -d)
  st_write "$PANE" @agent_state idle
  st_write "$p2"   @agent_state waiting
  t select-pane -t "$PANE"
  st_mirror_window "$PANE"
  [ "$(t display-message -p -t "$PANE" '#{@agent_window_state}')" = waiting ]
}

@test "sequence numbers increase monotonically" {
  local a b
  a=$(st_next_seq "$PANE")
  st_write "$PANE" @agent_seq "$a"
  b=$(st_next_seq "$PANE")
  [ "$b" -gt "$a" ]
}

@test "the lock is exclusive and recovers from a dead holder" {
  st_lock "$PANE"
  local dir="$ST_LOCK_DIR"
  [ -d "$dir" ]
  # A holder pid that cannot exist: the lock must be broken, not waited on.
  echo 99999999 > "$dir/pid"
  ST_LOCK_DIR=''
  run timeout 5 bash -c ". '$BONSAI_SCRIPTS/_state.sh'; st_lock '$PANE' 2 && echo took"
  [ "$output" = "took" ]
  rm -rf "$dir"
}

@test "events log appends JSON and is created 0600" {
  ev_append "$(ev_json ts# 1700000000 pane "$PANE" state waiting ask 'Bash: npm test')"
  local f; f=$(st_events_file)
  [ -f "$f" ]
  run jq -r '.state' "$f"
  [ "$output" = waiting ]
  run bash -c "ls -l '$f' | cut -c1-10"
  [ "$output" = "-rw-------" ]
}

@test "events JSON escapes quotes and backslashes in prompts" {
  ev_append "$(ev_json pane "$PANE" prompt 'he said "hi" \ then left')"
  run bash -c "tail -1 '$(st_events_file)' | jq -r '.prompt'"
  [ "$output" = 'he said "hi" \ then left' ]
}

@test "events log rotates past its size cap" {
  local f; f=$(st_events_file)
  mkdir -p "$(dirname "$f")"
  head -c 1100000 /dev/zero | tr '\0' 'x' > "$f"
  ev_append "$(ev_json pane "$PANE" state done)"
  [ -f "$(bs_state_dir)/events.1.jsonl" ]
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 1 ]
}

@test "settings persist to settings.tmux and apply live" {
  settings_set @bonsai-notify off
  [ "$(t show-option -gqv @bonsai-notify)" = off ]
  run cat "$(st_settings_file)"
  [[ "$output" == *"set -g @bonsai-notify 'off'"* ]]
  # Setting it again replaces rather than appends.
  settings_set @bonsai-notify on
  run bash -c "grep -c '@bonsai-notify ' '$(st_settings_file)'"
  [ "$output" = 1 ]
}

@test "settings values containing single quotes survive the file round trip" {
  local val="curl -d \"it's me\" https://example.invalid"
  settings_set @bonsai-notify-command "$val"
  [ "$(t show-option -gqv @bonsai-notify-command)" = "$val" ]
  # And a fresh tmux reading the file back gets the same thing.
  t set-option -gu @bonsai-notify-command
  t source-file "$(st_settings_file)"
  [ "$(t show-option -gqv @bonsai-notify-command)" = "$val" ]
}

@test "pinned options are reported from @bonsai-pinned" {
  t set-option -g @bonsai-pinned '@bonsai-notify @bonsai-glyphs'
  settings_pinned @bonsai-notify
  ! settings_pinned @bonsai-notify-input
}
