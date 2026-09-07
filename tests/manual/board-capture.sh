#!/usr/bin/env bash
# Reproduce the collector benchmark and terminal screenshot on a private server.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export BONSAI_TEST_TMP
BONSAI_TEST_TMP=$(mktemp -d "/tmp/bonsai-board-capture.XXXXXX")
export BONSAI_SOCKET="$BONSAI_TEST_TMP/tmux.sock"
trap 'tmux -S "$BONSAI_SOCKET" kill-server 2>/dev/null || :; rm -rf "$BONSAI_TEST_TMP"' EXIT
TMUX='' tmux -S "$BONSAI_SOCKET" -f /dev/null new-session -d -s agents -x 140 -y 32
. "$ROOT/tests/helper.sh"
setup_test
mkdir -p "$TMP/demo-project"
git -C "$TMP/demo-project" init -q
git -C "$TMP/demo-project" symbolic-ref HEAD refs/heads/demo-worktree
now=$(date +%s)
first=''
for number in $(seq 1 30); do
 pane=$(test_pane "$TMP/demo-project")
 [ -n "$first" ] || first=$pane
 case "$((number%5))" in
  1) state=waiting; text='Bash: npm test — allow?'; agent=claude;;
  2) state=working; text='Review the retry implementation'; agent=codex;;
  3) state='done'; text='Fixed the race in retry.spec'; agent=claude;;
  4) state=error; text='API error: retry budget exhausted'; agent=opencode;;
  0) state=idle; text='Completed and reviewed'; agent=claude;;
 esac
 tmx set -p -t "$pane" @agent_type "$agent" \; set -p -t "$pane" @agent_state "$state" \; set -p -t "$pane" @agent_state_ts "$((now-1200+number))" \; set -p -t "$pane" @agent_ask "$text" \; set -p -t "$pane" @agent_prompt "$text" \; set -p -t "$pane" @agent_msg "$text"
done
python3 - "$BONSAI_SCRIPTS/list.sh" <<'PY'
import statistics, subprocess, sys, time
samples=[]
for _ in range(11):
    started=time.perf_counter()
    subprocess.check_output([sys.argv[1], '--rows'])
    samples.append((time.perf_counter()-started)*1000)
print(f'30 panes: cold {samples[0]:.1f}ms; warm median {statistics.median(samples[1:]):.1f}ms; warm max {max(samples[1:]):.1f}ms')
PY
command=$(printf '%q ' "$BONSAI_SCRIPTS/board.sh" --watch)
board=$(tmx new-window -d -P -F '#{pane_id}' "$command")
sleep 0.5
tmx set -p -t "$first" @agent_ask 'PUSH-REFRESH-VERIFIED: Bash npm test — allow?'
python3 - "$BONSAI_SCRIPTS/board.sh" "$BONSAI_SOCKET" "$board" "$BONSAI_TEST_TMP/board.txt" <<'PY'
import subprocess, sys, time
started=time.perf_counter()
subprocess.check_call([sys.argv[1], '--refresh'])
for _ in range(40):
    capture=subprocess.check_output(['tmux','-S',sys.argv[2],'capture-pane','-p','-t',sys.argv[3]],text=True)
    if 'PUSH-REFRESH-VERIFIED' in capture:
        print(f'Push refresh visible after {(time.perf_counter()-started)*1000:.1f}ms')
        break
    time.sleep(.025)
else:
    raise SystemExit('Push refresh did not update the live fzf board')
with open(sys.argv[4],'w') as out: out.write(capture)
PY
python3 - "$BONSAI_TEST_TMP/board.txt" "$ROOT/docs/assets/board.svg" <<'PY'
import html, sys
lines=open(sys.argv[1]).read().rstrip().splitlines()
width=1180; height=48+len(lines)*19
with open(sys.argv[2],'w') as out:
    out.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n')
    out.write('<title>Actual bonsai agent board captured from a private tmux server</title>\n')
    out.write(f'<rect width="{width}" height="{height}" rx="10" fill="#15181e"/>\n')
    out.write('<g fill="#dedee3" font-family="Menlo,Consolas,monospace" font-size="13" xml:space="preserve">\n')
    for index,line in enumerate(lines):
        out.write(f'<text x="16" y="{29+index*19}">{html.escape(line)}</text>\n')
    out.write('</g></svg>\n')
print('Wrote docs/assets/board.svg from the live terminal capture')
PY
