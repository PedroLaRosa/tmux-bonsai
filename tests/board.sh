#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/helper.sh"
setup_test
p1=$(test_pane)
p2=$(test_pane)
p3=$(test_pane)
shell_pane=$(test_pane)
now=$(date +%s)
tmx set -p -t "$p1" @agent_type claude \; set -p -t "$p1" @agent_state waiting \; set -p -t "$p1" @agent_state_ts "$((now-20))" \; set -p -t "$p1" @agent_ask $'first\037second\nthird'
tmx set -p -t "$p2" @agent_type codex \; set -p -t "$p2" @agent_state waiting \; set -p -t "$p2" @agent_state_ts "$((now-10))"
tmx set -p -t "$p3" @agent_type claude \; set -p -t "$p3" @agent_state 'done' \; set -p -t "$p3" @agent_state_ts "$now" \; set -p -t "$p3" @agent_seen_ts 0
json=$("$BONSAI_SCRIPTS/list.sh" --json)
assert_jq "$json" ".[0].pane_id==\"$p1\" and .[1].pane_id==\"$p2\""
assert_jq "$json" "any(.[]; .pane_id==\"$p3\" and .unseen and .state==\"done\")"
assert_jq "$json" "all(.[]; .pane_id!=\"$shell_pane\")"
assert_jq "$json" 'all(.[]; (.ask|contains("\u001f") or contains("\n"))|not)'
# Every ASCII control byte is removed without eating Unicode or breaking the
# record boundary, independent of the tmux server's regex collation.
all_controls=$'\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177'
tmx set -p -t "$p1" @agent_ask "before${all_controls}café 🤖"
assert_jq "$("$BONSAI_SCRIPTS/list.sh" --json)" "any(.[]; .pane_id==\"$p1\" and .ask==(\"before\"+(\" \"*32)+\"café 🤖\"))"
# Reproduce tmux 3.4 output quoting even when this suite uses a newer server:
# its stdout turns US into literal \037 while preserving framing TABs.
command() {
 if [ "${1:-}" = tmux ]; then
  builtin command "$@" | LC_ALL=C sed 's/'$'\037''/\\037/g'
 else builtin command "$@"; fi
}
export -f command
legacy_json=$("$BONSAI_SCRIPTS/list.sh" --json)
unset -f command
assert_jq "$legacy_json" ".[0].pane_id==\"$p1\" and .[1].pane_id==\"$p2\""
assert_jq "$legacy_json" 'all(.[]; (.ask|contains("\u001f") or contains("\n"))|not)'
# Simulate an incomplete tmux record. Fail with a framing diagnostic instead of
# a jq null-index crash or a misleading empty/partial list of agents.
command() {
 if [ "${1:-}" = tmux ] && [ "${4:-}" = list-panes ]; then
  printf '%%123\037fragment\n'; return 0
 fi
 builtin command "$@"
}
export -f command
set +e
"$BONSAI_SCRIPTS/list.sh" --json > "$TMP/broken-snapshot.json" 2> "$TMP/broken-snapshot.err"
broken_status=$?
set -e
unset -f command
assert_eq 1 "$broken_status" 'malformed snapshot rejected'
assert_eq '' "$(cat "$TMP/broken-snapshot.json")" 'no misleading partial snapshot'
assert_contains "$(cat "$TMP/broken-snapshot.err")" 'invalid pane snapshot at record 1'

rows=$("$BONSAI_SCRIPTS/list.sh" --rows)
assert_eq 8 "$(printf '%s\n' "$rows" | awk -F '\037' 'NR==1 {print NF}')" 'stable row fields'
assert_eq '2 0 0 1 1 0 0 0' "$("$BONSAI_SCRIPTS/list.sh" --counts)" counts
all=$("$BONSAI_SCRIPTS/list.sh" --json --all)
assert_jq "$all" "any(.[]; .pane_id==\"$shell_pane\" and .state==\"shell\")"
# A window mirror must not count a shell sibling as a second agent.
sibling=$(tmx split-window -d -h -P -F '#{pane_id}' -t "$p1" 'sleep 3600')
tmx set -w -t "$p1" @agent_state waiting
assert_eq '2 0 0 1 1 0 0 0' "$("$BONSAI_SCRIPTS/list.sh" --counts)" 'window mirror ignored on shell sibling'
assert_contains "$("$BONSAI_SCRIPTS/status.sh")" '●2'
assert_contains "$("$BONSAI_SCRIPTS/board.sh" --header)" '2 needs you'
tmx kill-pane -t "$sibling"
# A complete state is exposed to scripts; timeout is distinguishable from errors.
assert_contains "$("$BONSAI_SCRIPTS/wait.sh" --pane "$p3" --for 'done' --timeout 0)" "$p3 done"
set +e
"$BONSAI_SCRIPTS/wait.sh" --pane "$p1" --for 'done' --timeout 0 --json > "$TMP/timeout.json"
result=$?
set -e
assert_eq 124 "$result"
assert_jq "$(cat "$TMP/timeout.json")" '.error=="timeout"'
# Literal text that resembles key names and shell substitution stays in the TTY.
input_pane=$(tmx new-window -d -P -F '#{pane_id}' 'cat')
tmx set -p -t "$input_pane" @agent_type manual \; set -p -t "$input_pane" @agent_state idle
literal='C-c $(touch /tmp/bonsai-must-not-exist) "quoted"'
"$BONSAI_SCRIPTS/reply.sh" "$input_pane" --yes -- "$literal"
sleep 0.1
assert_contains "$("$BONSAI_SCRIPTS/capture.sh" "$input_pane")" "$literal"
# Working/shell agents cannot receive a reply even with --yes.
if "$BONSAI_SCRIPTS/reply.sh" "$shell_pane" --yes blocked >/dev/null 2>&1; then echo 'reply allowed a shell' >&2; exit 1; fi
tmx set -p -t "$input_pane" @agent_state working
if "$BONSAI_SCRIPTS/reply.sh" "$input_pane" --yes blocked >/dev/null 2>&1; then echo 'reply allowed a working agent' >&2; exit 1; fi
tmx set -p -t "$input_pane" @agent_state idle
# Refusal has no side effects.
printf 'n\n' | "$BONSAI_SCRIPTS/reply.sh" "$input_pane" refused >/dev/null && { echo 'reply refusal unexpectedly succeeded' >&2; exit 1; }
# Shell snapshots become exited only after the stale threshold, preserving fresh hooks.
tmx set -p -t "$p3" @agent_state_ts "$((now-30000))" \; set -p -t "$p3" @agent_session test-session
assert_jq "$("$BONSAI_SCRIPTS/list.sh" --json)" "any(.[]; .pane_id==\"$p3\" and .state==\"exited\" and .resumable)"
# Fast age updates and event pushes use a prunable registration rather than a daemon.
ports_dir=$("$BONSAI_SCRIPTS/board.sh" --ports-dir)
mkdir -p "$ports_dir"
printf '1\n' > "$ports_dir/99999999"
"$BONSAI_SCRIPTS/board.sh" --refresh
[ ! -f "$ports_dir/99999999" ]
for pane in "$p1" "$p2" "$p3" "$shell_pane" "$input_pane"; do tmx kill-pane -t "$pane"; done
# An actual fzf TTY catches invalid binding syntax and missing listener exports.
if command -v fzf >/dev/null && command -v curl >/dev/null; then
 board_command=$(printf '%q ' "$BONSAI_SCRIPTS/board.sh" --watch --compact)
 board_pane=$(tmx new-window -d -P -F '#{pane_id}' "$board_command")
 sleep 0.5
 assert_contains "$(tmx capture-pane -p -t "$board_pane")" 'agents>'
 found=0
 for registration in "$ports_dir/"*; do [ ! -f "$registration" ] || found=1; done
 assert_eq 1 "$found" 'fzf listener registered'
 "$BONSAI_SCRIPTS/board.sh" --refresh
 tmx kill-pane -t "$board_pane"
fi
# Spawn and fanout exercise the orchestration flow with a local agent fixture.
# Worktrees already exist here; creation remains covered by worktrunk itself.
mkdir -p "$TMP/repo" "$HOME/.local/bin"
git -C "$TMP/repo" init -q
git -C "$TMP/repo" -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm initial
git -C "$TMP/repo" worktree add -qb board-worker-one "$TMP/worker-one"
git -C "$TMP/repo" worktree add -qb board-worker-two "$TMP/worker-two"
cat > "$HOME/.local/bin/bonsai-test-agent" <<'AGENT'
#!/usr/bin/env bash
. "$BONSAI_SCRIPTS/_lib.sh"
tmx set -p -t "$TMUX_PANE" @agent_type bonsai-test-agent \; set -p -t "$TMUX_PANE" @agent_state idle
IFS= read -r task
printf 'received: %s\n' "$task"
tmx set -p -t "$TMUX_PANE" @agent_state 'done'
sleep 5
AGENT
chmod +x "$HOME/.local/bin/bonsai-test-agent"
# The test server pre-dates this suite's temporary HOME and PATH.
tmx set-environment -g BONSAI_SCRIPTS "$BONSAI_SCRIPTS"
tmx set-environment -g PATH "$HOME/.local/bin:$PATH"
spawned=$(cd "$TMP/repo" && "$BONSAI_SCRIPTS/spawn.sh" --branch board-worker-one --agent "$HOME/.local/bin/bonsai-test-agent" --prompt 'test prompt' --yes)
"$BONSAI_SCRIPTS/wait.sh" --pane "$spawned" --for 'done' --timeout 5 >/dev/null
assert_contains "$("$BONSAI_SCRIPTS/capture.sh" "$spawned")" 'received: test prompt'
fanout=$(cd "$TMP/repo" && "$BONSAI_SCRIPTS/spawn.sh" --fanout --branches board-worker-one,board-worker-two --agent "$HOME/.local/bin/bonsai-test-agent" --prompt 'shared task' --yes)
assert_eq 2 "$(printf '%s\n' "$fanout" | wc -l | tr -d ' ')"
while IFS= read -r pane; do
 "$BONSAI_SCRIPTS/wait.sh" --pane "$pane" --for 'done' --timeout 5 >/dev/null
 assert_contains "$("$BONSAI_SCRIPTS/capture.sh" "$pane")" 'received: shared task'
 tmx kill-pane -t "$pane"
done <<< "$fanout"
tmx kill-pane -t "$spawned"

# Servers sharing a state directory must never refresh each other's listener.
other_socket="$TMP/other.sock"
TMUX='' tmux -S "$other_socket" -f /dev/null new-session -d -s other
tmux -S "$other_socket" set -g @bonsai-state-dir "$(bonsai_state_dir)"
other_ports=$(BONSAI_SOCKET="$other_socket" "$BONSAI_SCRIPTS/board.sh" --ports-dir)
[ "$other_ports" != "$ports_dir" ]
printf '1\n' > "$ports_dir/99999999"
BONSAI_SOCKET="$other_socket" "$BONSAI_SCRIPTS/board.sh" --refresh
[ -f "$ports_dir/99999999" ]
tmux -S "$other_socket" kill-server

# Verification belongs to the backend that was actually tested.
tmx set -g @bonsai-notify on \; set -g @bonsai-notify-backend command \; set -g @bonsai-notify-command /usr/bin/true
printf '{"ts":%s,"backend":"command","outcome":"verified"}\n' "$(date +%s)" > "$(bonsai_state_dir)/notify-verify"
case "$("$BONSAI_SCRIPTS/status.sh")" in *'!'*) echo 'current verification rejected' >&2; exit 1;; esac
tmx set -g @bonsai-notify-backend none
assert_contains "$("$BONSAI_SCRIPTS/status.sh")" '!'
assert_contains "$("$BONSAI_SCRIPTS/board.sh" --header)" 'notifications unverified'
tmx set -g @bonsai-notify off

# Feed rows and JSON read the real hydrated log record, including nested notify.
. "$BONSAI_SCRIPTS/_notify.sh"
feed_pane=$(test_pane)
tmx set -p -t "$feed_pane" @agent_type claude \; set -p -t "$feed_pane" @agent_state 'done' \; set -p -t "$feed_pane" @agent_msg 'A completed task'
: > "$(bonsai_state_dir)/events.jsonl"
bonsai_log "$feed_pane" Stop working 'done' finished delivered command test-delivered
bonsai_log "$feed_pane" Stop working 'done' finished cooldown command test-suppressed
assert_jq "$("$BONSAI_SCRIPTS/feed.sh" --json)" 'length==2 and .[0].notify.decision=="cooldown"'
assert_jq "$("$BONSAI_SCRIPTS/feed.sh" --json --why)" 'length==1 and .[0].notify.decision=="cooldown"'
assert_contains "$("$BONSAI_SCRIPTS/feed.sh" --rows)" 'delivered (command)'
why_rows=$("$BONSAI_SCRIPTS/feed.sh" --rows --why)
assert_contains "$why_rows" 'cooldown (command)'
case "$why_rows" in *'delivered'*) echo 'why feed includes delivered record' >&2; exit 1;; esac
# Replace only the streaming file follower: exercise the actual tail formatter
# and JSON filter without leaving a long-running tail process in the test suite.
tail() { local file; for file in "$@"; do :; done; cat "$file"; }
export -f tail
assert_contains "$("$BONSAI_SCRIPTS/feed.sh" --tail)" 'delivered (command)'
assert_jq "$("$BONSAI_SCRIPTS/feed.sh" --tail --json --why | jq -s .)" 'length==1 and .[0].notify.decision=="cooldown"'
assert_contains "$("$BONSAI_SCRIPTS/feed.sh" --tail --rows --why)" 'cooldown (command)'
unset -f tail

# Terminal activation accepts an explicit bundle ID and shares auto detection.
tmx set -g @bonsai-terminal com.googlecode.iterm2
assert_eq com.googlecode.iterm2 "$(bonsai_terminal)"
# Stub the activation command so this regression never opens a desktop app.
open() { printf '%s\n' "$*" > "$TMP/jump-open"; }
uname() { printf 'Darwin\n'; }
export TMP
export -f open uname
"$BONSAI_SCRIPTS/jump.sh" "$feed_pane"
assert_eq '-b com.googlecode.iterm2' "$(cat "$TMP/jump-open")"
unset -f open uname
tmx set -g @bonsai-terminal auto
tmx kill-pane -t "$feed_pane"
