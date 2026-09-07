#!/usr/bin/env bash
# Optional benchmark, excluded from run.sh: measures actual process launch/EOF.
set -euo pipefail
command -v python3 >/dev/null || { echo 'python3 is required for this benchmark only'; exit 1; }
export BONSAI_LATENCY_ROOT
BONSAI_LATENCY_ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - <<'PY'
from pathlib import Path
import json, os, shutil, statistics, subprocess, tempfile, time

with tempfile.TemporaryDirectory(prefix='bonsai-hook-latency-') as folder:
    root = Path(folder)
    shutil.copytree(Path(os.environ['BONSAI_LATENCY_ROOT'])/'scripts/hooks', root/'scripts/hooks')
    reducer = root/'scripts/agent-event.sh'
    reducer.write_text('#!/usr/bin/env bash\nexit 0\n')
    reducer.chmod(0o755)
    env = dict(os.environ, TMUX_PANE='%99')
    env.pop('CLAUDE_JOB_DIR', None)
    env.pop('BONSAI_EVENT_SEQ', None)
    command = [str(root/'scripts/hooks/hook-claude.sh'), 'PostToolUse']
    payload = json.dumps({'tool_name':'Bash','tool_input':{'command':''}}).encode()
    payload = json.dumps({'tool_name':'Bash','tool_input':{'command':'x'*(4096-len(payload))}}).encode()
    assert len(payload) == 4096
    samples = []
    for _ in range(40):
        start = time.perf_counter()
        result = subprocess.run(command, input=payload,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, check=True)
        assert result.stdout == b'' and result.stderr == b''
        samples.append((time.perf_counter()-start)*1000)
    median = statistics.median(samples)
    p95 = sorted(samples)[37]
    print('Foreground hook: median %.2f ms, p95 %.2f ms, max %.2f ms (40 launches, 4 KB payload)' %
          (median, p95, max(samples)))
    print('p95 <15 ms target: ' + ('met' if p95 < 15 else 'missed on this host; timing is diagnostic, not a CI gate'))
    reducer.write_text('#!/usr/bin/env bash\nsleep 2\necho child-output\necho child-error >&2\n')
    result = subprocess.run(command, input=b'{}', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=env, check=True, timeout=1)
    assert result.stdout == b'' and result.stderr == b''
    print('Inherited pipe EOF: passed (hook returned while reducer slept for 2 seconds)')
PY
