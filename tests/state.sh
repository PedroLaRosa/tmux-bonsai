#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/helper.sh"
setup_test
source "$BONSAI_SCRIPTS/_state.sh"
pane=$(test_pane)
export TMUX_PANE=$pane

event() { local payload=${3:-}; [ -n "$payload" ] || payload='{}'; printf '%s' "$payload" | "$BONSAI_SCRIPTS/agent-event.sh" "$1" "$2" --pane "$pane"; }
opt() { bonsai_pane_opt "$pane" "$1"; }

event claude SessionStart '{"source":"startup","session_id":"session-one","transcript_path":"/tmp/transcript"}'
assert_eq idle "$(opt @agent_state)" boundary
assert_eq session-one "$(opt @agent_session)"
assert_eq 1 "$(opt @agent_seq)"
assert_eq "$(opt @agent_state_ts)" "$(opt @agent_seen_ts)"
event claude UserPromptSubmit '{"prompt":"Fix the tests"}'
assert_eq working "$(opt @agent_state)"
assert_eq 'Fix the tests' "$(opt @agent_prompt)"
tmx set-option -p -t "$pane" @agent_state_ts 42
event claude PreToolUse '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
assert_eq 42 "$(opt @agent_state_ts)" 'tool churn keeps state age'
assert_eq 'Bash: npm test' "$(opt @agent_tool)"
event claude PermissionRequest '{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
assert_eq waiting "$(opt @agent_state)"
assert_eq 'Bash: npm test' "$(opt @agent_ask)"
assert_eq waiting "$(tmx show-option -wqv -t "$pane" @agent_state)"
event claude PostToolUse '{}'
assert_eq working "$(opt @agent_state)"
assert_eq '' "$(opt @agent_ask)"
assert_eq '' "$(opt @agent_tool)"
event claude PreToolUse '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database?"}]}}'
assert_eq waiting "$(opt @agent_state)"
assert_eq 'Question: Which database?' "$(opt @agent_ask)"
event claude Stop '{"last_assistant_message":"All tests pass"}'
assert_eq 'done' "$(opt @agent_state)"
assert_eq 'All tests pass' "$(opt @agent_msg)"
"$BONSAI_SCRIPTS/ack.sh" "$pane"
assert_eq 'done' "$(opt @agent_state)" 'ack retains completion event'
assert_jq "$(bonsai_snapshot "$pane")" '.seen_ts >= .state_ts'
"$BONSAI_SCRIPTS/ack.sh" "$pane" --unread
assert_eq 0 "$(opt @agent_seen_ts)"
tmx set-option -p -t "$pane" @agent_seen_ts "$(( $(date +%s) + 1 ))"
event claude UserPromptSubmit '{}'
event claude Stop '{}'
assert_jq "$(bonsai_snapshot "$pane")" '.seen_ts < .state_ts' 'same-second completion stays unseen'
event claude Stop '{"is_interrupt":true}'
assert_eq stopped "$(opt @agent_state)"
event claude StopFailure '{"error":"API failed"}'
assert_eq error "$(opt @agent_state)"
assert_eq 'API failed' "$(opt @agent_msg)"

# Stale hook delivery never overwrites a newer turn, even when detach reorders.
event claude UserPromptSubmit '{"prompt":"new turn","bonsai_seq":200}'
accepted_seq=$(opt @agent_seq)
event claude Stop '{"last_assistant_message":"old response","bonsai_seq":100}'
assert_eq working "$(opt @agent_state)"
assert_eq "$accepted_seq" "$(opt @agent_seq)"
assert_eq '' "$(opt @agent_msg)"
for incoming in 310 340 320 330; do
  printf '{"state":"waiting","ask":"event-%s","bonsai_seq":%s}' "$incoming" "$incoming" | "$BONSAI_SCRIPTS/agent-event.sh" manual mark --pane "$pane" &
done
wait
assert_eq 340 "$(opt @agent_source_seq)" 'concurrent source ordering'
assert_eq event-340 "$(opt @agent_ask)"
printf '{"state":"waiting","bonsai_seq":350}' | BONSAI_EVENT_SEQ=999 "$BONSAI_SCRIPTS/agent-event.sh" manual mark --pane "$pane"
assert_eq 350 "$(opt @agent_source_seq)" 'provider emission order precedes later hook process-start order'

# Literal shell/tmux syntax, backslashes and non-ASCII stay inert and intact.
event claude Stop '{"last_assistant_message":"$(touch /tmp/bonsai-injected) #{pane_id} C:\\work\\α"}'
assert_eq '$(touch /tmp/bonsai-injected) #{pane_id} C:\work\α' "$(opt @agent_msg)"
event claude Stop '{"last_assistant_message":";"}'
assert_eq ';' "$(opt @agent_msg)"
event claude UserPromptSubmit "$(jq -cn '{prompt:("é" * 170 + "\n\u001b[31mred\u0007")}')"
assert_eq 160 "$(opt @agent_prompt | jq -Rrs 'length')" 'UTF-8 truncation'
event claude Stop '{"last_assistant_message":"hello\nworld\u001b[31m red\u0007"}'
assert_eq 'hello world red' "$(opt @agent_msg)"
tmx set-option -p -t "$pane" @agent_msg $'tab\tnewline\nFS\034US\037 literal \\037'
assert_jq "$(bonsai_snapshot "$pane")" '.msg == "tab newline FS US  literal \\037"' 'wire tabs preserve field framing without decoding literal escapes'
dollar_text='$literal ${name} $(command) \$escaped \\$twice $9 \037 $é \$é $😀 \$😀 $נ \$נ'
event claude Stop "$(jq -cn --arg message "$dollar_text" '{last_assistant_message:$message}')"
assert_eq "$dollar_text" "$(opt @agent_msg)" 'raw pane option preserves dollar and literal backslash text'
assert_eq "$dollar_text" "$(bonsai_snapshot "$pane" | jq -r .msg)" 'snapshot preserves dollar and literal backslash text'

# Child IDs make duplicate starts/stops idempotent, and parent Stop waits.
event claude UserPromptSubmit '{}'
event claude SubagentStart '{"agent_id":"a"}'
event claude SubagentStart '{"agent_id":"a"}'
event claude SubagentStart '{"agent_id":"b"}'
assert_eq 2 "$(opt @agent_children)"
event claude Stop '{"last_assistant_message":"Parent finished"}'
assert_eq working "$(opt @agent_state)"
event claude SubagentStop '{"agent_id":"a"}'
assert_eq working "$(opt @agent_state)"
event claude SubagentStop '{"agent_id":"b"}'
assert_eq 'done' "$(opt @agent_state)"
assert_eq 0 "$(opt @agent_children)"
event claude SubagentStop '{"agent_id":"b"}'
assert_eq 0 "$(opt @agent_children)"

event claude UserPromptSubmit '{}'
event claude SessionStart '{"source":"compact"}'
assert_eq working "$(opt @agent_state)" 'mid-turn compact ignored'
event claude PostCompact '{"trigger":"manual"}'
assert_eq 'done' "$(opt @agent_state)"
event claude SessionEnd '{}'
assert_eq exited "$(opt @agent_state)"
event claude StatusLine '{"model":{"display_name":"Opus\n4"},"context_window":{"used_percentage":42}}'
assert_eq 'Opus 4' "$(opt @agent_model)"
assert_eq 42 "$(opt @agent_ctx)"
generation=$(opt @agent_generation)
event claude StatusLine '{"context_window":{"used_percentage":43}}'
assert_eq "$generation" "$(opt @agent_generation)" 'metadata preserves notification generation'

event codex agent-turn-complete '{"input-messages":["first","last"],"last-assistant-message":"Shipped"}'
assert_eq 'done' "$(opt @agent_state)"
assert_eq last "$(opt @agent_prompt)"
assert_eq Shipped "$(opt @agent_msg)"
assert_eq notify "$(opt @agent_hook_mode)"
event title title '{"classification":"working"}'
assert_eq working "$(opt @agent_state)" 'notify-only Codex can work from titles'
event codex UserPromptSubmit '{"prompt":"Native hook turn"}'
assert_eq native "$(opt @agent_hook_mode)"
event title title '{"classification":"idle"}'
assert_eq working "$(opt @agent_state)" 'Codex native hooks win fresh idle titles'
event gemini BeforeAgent '{"prompt":"Use a tool"}'
event title title '{"classification":"permission"}'
assert_eq waiting "$(opt @agent_state)" 'Gemini permission title supplements hooks'
event opencode session.created '{"properties":{"info":{"id":"root"}}}'
assert_eq idle "$(opt @agent_state)"
assert_eq root "$(opt @agent_session)"
event opencode session.status '{"properties":{"status":{"type":"busy"}}}'
assert_eq working "$(opt @agent_state)"
event opencode SubagentStart '{"agent_id":"opencode-child","root_session_id":"root"}'
assert_eq 1 "$(opt @agent_children)"
event opencode SubagentStop '{"agent_id":"opencode-child","root_session_id":"root"}'
assert_eq 0 "$(opt @agent_children)"
event opencode message.part.updated '{"properties":{"role":"assistant","part":{"type":"text","text":"Updated files"}}}'
event opencode session.idle '{}'
assert_eq 'done' "$(opt @agent_state)"
assert_eq 'Updated files' "$(opt @agent_msg)"
event opencode question.asked '{"properties":{"questions":[{"question":"Continue?"}]}}'
assert_eq waiting "$(opt @agent_state)"
event opencode question.replied '{}'
assert_eq working "$(opt @agent_state)"
event opencode session.error '{"properties":{"error":{"data":{"message":"Disconnected"}}}}'
assert_eq error "$(opt @agent_state)"
assert_eq Disconnected "$(opt @agent_msg)"

assert_eq working "$("$BONSAI_SCRIPTS/title.sh" --classify '⢿ Claude')"
assert_eq working "$("$BONSAI_SCRIPTS/title.sh" --classify '◒ Codex')"
assert_eq permission "$("$BONSAI_SCRIPTS/title.sh" --classify '✋ Gemini')"
assert_eq permission "$("$BONSAI_SCRIPTS/title.sh" --classify '✋ ⠙ Gemini')"
assert_eq idle "$("$BONSAI_SCRIPTS/title.sh" --classify 'Codex Ready')"
# This is an intentionally literal title, not a home directory path.
# shellcheck disable=SC2088
assert_eq none "$("$BONSAI_SCRIPTS/title.sh" --classify '~/codex/ready')"
assert_eq none "$("$BONSAI_SCRIPTS/title.sh" --classify 'reworking')"
assert_eq none "$("$BONSAI_SCRIPTS/title.sh" --classify 'not-ready')"
assert_eq none "$("$BONSAI_SCRIPTS/title.sh" --classify 'Cursor Agent running')"
title_format=$("$BONSAI_SCRIPTS/title.sh" --format)
for title_case in '⢿ Claude' '◒ Codex' '✋ ⠙ Gemini' 'Codex Ready' 'ready.' '(thinking)' 'repo/done' 'C:\agent\ready' 'not-ready' 'reworking' 'Cursor Agent running' 'claude agents ⠙' '✳ working' 'working done' '⠙ ready'; do
  tmx select-pane -t "$pane" -T "$title_case"
  assert_eq "$("$BONSAI_SCRIPTS/title.sh" --classify "$title_case")" "$(tmx display-message -p -t "$pane" "$title_format")" "tmux/title classifier parity: $title_case"
done
# Cover all 256 frames, including ones outside the common ten-dot spinner.
while IFS= read -r glyph; do
  tmx select-pane -t "$pane" -T "$glyph Claude"
  assert_eq working "$(tmx display-message -p -t "$pane" "$title_format")" "braille title frame: $glyph"
done < <(jq -nr 'range(10240;10496) | [.] | implode')
for title_case in '⟿ unrelated' '⤀ unrelated'; do
  tmx select-pane -t "$pane" -T "$title_case"
  assert_eq none "$(tmx display-message -p -t "$pane" "$title_format")" 'braille range boundary'
done
untracked=$(test_pane)
tmx select-pane -t "$untracked" -T '⠙ unrelated process'
"$BONSAI_SCRIPTS/title.sh" "$untracked"
assert_eq working "$(bonsai_pane_opt "$untracked" @agent_title_state)" 'unrecognized spinner classification cached'
assert_eq '' "$(bonsai_pane_opt "$untracked" @agent_type)"
assert_eq '' "$(bonsai_pane_opt "$untracked" @agent_state)"
cat > "$TMP/codex" <<'AGENT'
#!/usr/bin/env bash
sleep 3600
AGENT
chmod +x "$TMP/codex"
hookless=$(tmx new-window -d -P -F '#{pane_id}' "$TMP/codex")
tmx select-pane -t "$hookless" -T '⠙ Codex'
"$BONSAI_SCRIPTS/title.sh" "$hookless"
assert_eq codex "$(bonsai_pane_opt "$hookless" @agent_type)" 'title detects a descendant agent process'
assert_eq working "$(bonsai_pane_opt "$hookless" @agent_state)"
tmx select-pane -t "$hookless" -T 'Codex ready'
"$BONSAI_SCRIPTS/title.sh" "$hookless"
assert_eq 'done' "$(bonsai_pane_opt "$hookless" @agent_state)" 'hookless idle title completes working'
event claude UserPromptSubmit '{}'
event title title '{"classification":"idle"}'
event title title-settled '{}'
assert_eq working "$(opt @agent_state)" 'fresh hooks win idle titles'
tmx set-option -p -t "$pane" @agent_hook_ts 1 \; set-option -p -t "$pane" @agent_title_ts 1
event title title-settled '{"expected_seq":0}'
assert_eq working "$(opt @agent_state)" 'settle generation prevents stale inference'
event title title-settled '{}'
assert_eq stopped "$(opt @agent_state)"
event claude UserPromptSubmit '{}'
event title title '{"classification":"idle"}'
tmx set-option -p -t "$pane" @agent_hook_ts 1 \; set-option -p -t "$pane" @agent_title_ts 1
settle_seq=$(opt @agent_seq)
for context in 41 42 43; do
  event claude StatusLine "{\"context_window\":{\"used_percentage\":$context}}"
done
"$BONSAI_SCRIPTS/title.sh" --settle "$pane" "$settle_seq" 0.4
assert_eq stopped "$(opt @agent_state)" 'metadata sequence changes do not restart an elapsed title quiet interval'

# Two panes in one window retain the most severe mirror regardless of writer.
other=$(tmx split-window -d -t "$pane" -P -F '#{pane_id}' 'sleep 3600')
assert_jq "$(bonsai_snapshot "$other")" '.state == "unknown"' 
printf '{"state":"waiting"}' | "$BONSAI_SCRIPTS/agent-event.sh" manual mark --pane "$other"
assert_eq manual "$(bonsai_pane_opt "$other" @agent_type)"
event manual mark '{"state":"done"}'
assert_eq waiting "$(tmx show-option -wqv -t "$pane" @agent_state)"
"$BONSAI_SCRIPTS/clear-markers.sh" "$other"
assert_eq 'done' "$(tmx show-option -wqv -t "$pane" @agent_state)" 'untracked shell does not retain old window mirror'
printf '{"state":"waiting"}' | "$BONSAI_SCRIPTS/agent-event.sh" manual mark --pane "$other"

# Focus entries and logs are private and scoped to a tmux socket.
"$BONSAI_SCRIPTS/focus.sh" in /dev/test-bonsai
assert_contains "$(cat "$(bonsai_focus_file)")" /dev/test-bonsai
"$BONSAI_SCRIPTS/focus.sh" out /dev/test-bonsai
assert_eq '' "$(cat "$(bonsai_focus_file)")"
log="$(bonsai_state_dir)/events.jsonl"
jq -e -s 'length > 10 and all(.[]; .pane != null and .event != null)' "$log" >/dev/null
dd if=/dev/zero bs=1048576 count=1 2>/dev/null | tr '\000' ' ' > "$log"
bonsai_log "$pane" test 'done' 'done' input test fake id
assert_eq yes "$(test -f "$(bonsai_state_dir)/events.1.jsonl" && echo yes)"
jq -e '.notify.decision == "test"' "$log" >/dev/null
"$BONSAI_SCRIPTS/clear-markers.sh" "$pane"
assert_eq '' "$(opt @agent_type)"
assert_eq waiting "$(tmx show-option -wqv -t "$other" @agent_state)"
echo 'state: OK'
