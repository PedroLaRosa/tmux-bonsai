#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/helper.sh"
setup_test
source "$BONSAI_SCRIPTS/_state.sh"
pane=$(test_pane)
export TMUX_PANE=$pane BONSAI_TEST_RECORD="$TMP/notifications.jsonl"
record_backend="$TMP/record notification.sh"
cat > "$record_backend" <<'BACKEND'
#!/usr/bin/env bash
[ -z "${BONSAI_TEST_BACKEND_DELAY:-}" ] || sleep "$BONSAI_TEST_BACKEND_DELAY"
jq -nc '{pane:env.BONSAI_PANE,socket:env.BONSAI_SOCKET,category:env.BONSAI_CATEGORY,title:env.BONSAI_TITLE,body:env.BONSAI_BODY,agent:env.BONSAI_AGENT,state:env.BONSAI_STATE,id:env.BONSAI_ID,sound:env.BONSAI_SOUND,jump:env.BONSAI_JUMP_CMD}' >> "$BONSAI_TEST_RECORD"
exit "${BONSAI_TEST_BACKEND_EXIT:-0}"
BACKEND
chmod +x "$record_backend"
tmx set -g @bonsai-notify on \; set -g @bonsai-notify-backend command \; set -g @bonsai-notify-command "$record_backend" \; \
  set -g @bonsai-notify-focus off \; set -g @bonsai-notify-cooldown 0 \; set -g @bonsai-notify-grace 0 \; \
  set -g @bonsai-notify-input on \; set -g @bonsai-notify-finished on \; set -g @bonsai-notify-error on \; \
  set -g @bonsai-notify-on-bell on \; set -g @bonsai-notify-preview on \; set -g @bonsai-sound-mode off
seq=100
prepare() {
  seq=$((seq + 1))
  : > "$BONSAI_TEST_RECORD"
  tmx set -p -t "$pane" @agent_type claude \; set -p -t "$pane" @agent_state "${1:-waiting}" \; \
    set -p -t "$pane" @agent_seq "$seq" \; set -p -t "$pane" @agent_state_ts "$(date +%s)" \; \
    set -p -t "$pane" @agent_generation 0 \; \
    set -p -t "$pane" @agent_seen_ts 0 \; set -p -t "$pane" @agent_notified_ts 0 \; \
    set -p -t "$pane" @agent_hook_ts 0 \; set -p -t "$pane" @agent_ask 'Permission: secret value' \; \
    set -p -t "$pane" @agent_msg 'Assistant result' \; set -p -t "$pane" @agent_prompt 'Original prompt' \; \
    set -p -t "$pane" @agent_reminder_token ''
}
deliver() { "$BONSAI_SCRIPTS/notify.sh" deliver "$pane" "$@"; }
count() { jq -s 'length' "$BONSAI_TEST_RECORD"; }
decision() { jq -sr --arg pane "$pane" '[.[] | select(.pane == $pane and .event == "notification")] | last | .notify.decision' "$(bonsai_state_dir)/events.jsonl"; }

prepare
deliver input --seq "$seq"
assert_eq 1 "$(count)"
assert_jq "$(cat "$BONSAI_TEST_RECORD")" '.category == "input" and .body == "Permission: secret value" and .state == "waiting"'
assert_jq "$(cat "$BONSAI_TEST_RECORD")" ".pane == \"$pane\" and .id == \"bonsai-$pane\""
assert_contains "$(cat "$BONSAI_TEST_RECORD")" "$BONSAI_SOCKET"
assert_eq delivered "$(decision)"
assert_eq "bonsai-$pane" "$(bonsai_pane_opt "$pane" @agent_notify_id)"

prepare
tmx set -g @bonsai-notify off
deliver input
assert_eq 0 "$(count)"
assert_eq disabled "$(decision)"
tmx set -g @bonsai-notify on \; set -g @bonsai-notify-input off
deliver input
assert_eq 0 "$(count)"
assert_eq category-off "$(decision)"
tmx set -g @bonsai-notify-input on

prepare
tmx set -g @bonsai-notify-cooldown 5
deliver input
deliver input
assert_eq 1 "$(count)"
assert_eq cooldown "$(decision)"
prepare
tmx set -p -t "$pane" @agent_hook_ts "$(date +%s)"
deliver bell
assert_eq 0 "$(count)"
assert_eq cooldown "$(decision)" 'hook and terminal bell deduplicated'
tmx set -g @bonsai-notify-cooldown 0

prepare
tmx set -g @bonsai-notify-preview off
deliver input
assert_jq "$(cat "$BONSAI_TEST_RECORD")" '.body | contains("secret") | not'
tmx set -g @bonsai-notify-preview on

# Explicit tests use the actual backend while bypassing the user's gates.
prepare
tmx set -g @bonsai-notify off \; set -g @bonsai-notify-input off \; set -g @bonsai-notify-cooldown 5
tmx set -p -t "$pane" @agent_notified_ts "$(date +%s)"
deliver input --test
assert_eq 1 "$(count)"
assert_jq "$(cat "$BONSAI_TEST_RECORD")" '.title == "bonsai notifications are on" and .body == "Click to jump back to this pane"'
tmx set -g @bonsai-notify on \; set -g @bonsai-notify-input on \; set -g @bonsai-notify-cooldown 0

prepare
tmx set -g @bonsai-notify-backend unavailable-test-backend
if deliver input; then echo 'Missing backend unexpectedly succeeded' >&2; exit 1; fi
assert_eq backend-missing "$(decision)"
assert_eq 0 "$(count)"
tmx set -g @bonsai-notify-backend command
export BONSAI_TEST_BACKEND_EXIT=1
if deliver input; then echo 'Failed backend unexpectedly succeeded' >&2; exit 1; fi
assert_eq failed "$(decision)"
unset BONSAI_TEST_BACKEND_EXIT

# A delayed worker carries its originating generation, and done has a quiet
# interval to avoid announcing milestones while the same agent resumes.
prepare 'done'
tmx set -g @bonsai-notify-grace 0.4
deliver finished --seq "$seq" & worker=$!
sleep 0.1
tmx set -p -t "$pane" @agent_seq "$((seq + 1))" \; set -p -t "$pane" @agent_state working
wait "$worker"
assert_eq 0 "$(count)"
assert_eq grace-cancelled "$(decision)"
deliver finished --seq "$seq"
assert_eq 0 "$(count)" 'stale worker must not announce latest working state'
assert_eq grace-cancelled "$(decision)"
tmx set -g @bonsai-notify-grace 0

# Metadata increments accepted-event sequence but leaves state generation alone.
prepare 'done'
tmx set -p -t "$pane" @agent_generation 7
tmx set -g @bonsai-notify-grace 0.4
deliver finished --generation 7 & worker=$!
sleep 0.1
printf '{"model":{"display_name":"Opus"}}' | "$BONSAI_SCRIPTS/agent-event.sh" claude StatusLine --pane "$pane"
wait "$worker"
assert_eq 1 "$(count)" 'status metadata must not cancel completion grace'
assert_eq 7 "$(bonsai_pane_opt "$pane" @agent_generation)"
tmx set -g @bonsai-notify-grace 0

# The reservation lock deduplicates simultaneous backend calls.
prepare
tmx set -g @bonsai-notify-cooldown 5
export BONSAI_TEST_BACKEND_DELAY=0.2
deliver input --seq "$seq" & first=$!
deliver input --seq "$seq" & second=$!
wait "$first"; wait "$second"
assert_eq 1 "$(count)" 'concurrent notification cooldown'
unset BONSAI_TEST_BACKEND_DELAY
tmx set -g @bonsai-notify-cooldown 0

# Acknowledging cancels the scheduled reminder even if the user marks the pane
# unread again before the old sleeper wakes.
prepare
tmx set -p -t "$pane" @agent_reminder_token "$seq"
"$BONSAI_SCRIPTS/notify.sh" remind "$pane" "$seq" 0.4 & worker=$!
sleep 0.1
"$BONSAI_SCRIPTS/ack.sh" "$pane"
"$BONSAI_SCRIPTS/ack.sh" "$pane" --unread
wait "$worker"
assert_eq 0 "$(count)" 'ack cancels reminder generation'
prepare
tmx set -p -t "$pane" @agent_reminder_token "$seq"
"$BONSAI_SCRIPTS/notify.sh" remind "$pane" "$seq" 0
assert_eq 1 "$(count)"
assert_contains "$(cat "$BONSAI_TEST_RECORD")" 'still waiting'
prepare
tmx set -p -t "$pane" @agent_generation 8 \; set -p -t "$pane" @agent_reminder_token 8
"$BONSAI_SCRIPTS/notify.sh" remind "$pane" 8 0.4 & worker=$!
sleep 0.1
printf '{"properties":{"role":"assistant","part":{"type":"text","text":"Still awaiting approval"}}}' | "$BONSAI_SCRIPTS/agent-event.sh" opencode message.part.updated --pane "$pane"
wait "$worker"
assert_eq 1 "$(count)" 'preview metadata must not cancel input reminder'

# Use a real attached tmux client where Python's portable PTY API is available.
# This tests focus changes during grace, not just a mocked focus predicate.
if command -v python3 >/dev/null 2>&1; then
  cat > "$TMP/client.py" <<'CLIENT'
import os, pty, select, signal, subprocess, sys
master, slave = pty.openpty()
client = subprocess.Popen(["tmux", "-S", sys.argv[1], "attach-session", "-t", "test"],
                          stdin=slave, stdout=slave, stderr=slave,
                          env=dict(os.environ, TERM="xterm-256color"))
with open(sys.argv[2], "w") as output:
    output.write(os.ttyname(slave))
os.close(slave)
signal.signal(signal.SIGTERM, lambda *_: client.terminate())
try:
    while client.poll() is None:
        if select.select([master], [], [], 0.1)[0]:
            try:
                if not os.read(master, 65536): break
            except OSError: break
finally:
    client.terminate()
    client.wait()
    os.close(master)
CLIENT
  tmx select-window -t "$pane" \; select-pane -t "$pane"
  python3 "$TMP/client.py" "$BONSAI_SOCKET" "$TMP/client-tty" & client_runner=$!
  for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ ! -s "$TMP/client-tty" ] || [ -z "$(tmx list-clients -F '#{client_tty}')" ] || break
    sleep 0.1
  done
  tty=$(cat "$TMP/client-tty")
  prepare
  tmx set -g @bonsai-notify-focus strict
  "$BONSAI_SCRIPTS/focus.sh" in "$tty"
  assert_eq yes "$(bonsai_is_focused "$pane" strict && echo yes)"
  visible_sibling=$(tmx split-window -d -t "$pane" -P -F '#{pane_id}' 'sleep 3600')
  assert_eq yes "$(bonsai_is_focused "$visible_sibling" attached && echo yes)" 'attached suppression covers visible inactive splits'
  if bonsai_is_focused "$visible_sibling" strict; then echo 'Inactive split incorrectly has strict focus' >&2; exit 1; fi
  tmx resize-pane -Z -t "$pane"
  if bonsai_is_focused "$visible_sibling" attached; then echo 'Zoom-hidden split incorrectly visible' >&2; exit 1; fi
  tmx resize-pane -Z -t "$pane"
  deliver input
  assert_eq 0 "$(count)"
  assert_eq suppressed-focus "$(decision)"
  "$BONSAI_SCRIPTS/focus.sh" out "$tty"
  if bonsai_is_focused "$pane" strict; then echo 'Focus-out retained strict focus' >&2; exit 1; fi
  assert_eq yes "$(bonsai_is_focused "$pane" attached && echo yes)"
  prepare 'done'
  tmx set -g @bonsai-notify-grace 0.4
  deliver finished --seq "$seq" & worker=$!
  sleep 0.1
  "$BONSAI_SCRIPTS/focus.sh" in "$tty"
  wait "$worker"
  assert_eq 0 "$(count)" 'focus during grace suppresses pending banner'
  assert_eq suppressed-focus "$(decision)"
  "$BONSAI_SCRIPTS/focus.sh" out "$tty"
  kill "$client_runner" 2>/dev/null || true
  wait "$client_runner" || true
  tmx set -g @bonsai-notify-focus off \; set -g @bonsai-notify-grace 0
fi

prepare
dead=$(test_pane)
tmx kill-pane -t "$dead"
"$BONSAI_SCRIPTS/notify.sh" deliver "$dead" input
assert_eq 0 "$(count)" 'dead panes are ignored'
echo 'notify: OK'
