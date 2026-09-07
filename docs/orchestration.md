# Orchestrating agents

The `bonsai` CLI uses the server named by `$TMUX`. Outside tmux, pass `bonsai -S /path/to/socket …`; notification click handlers do the same. Install the agent hooks first (`bonsai hooks install claude`) so workers report readiness and completion.

This example starts three Claude workers, waits for each, and captures the results:

```bash
cat > task.md <<'TASK'
Review the retry implementation. Add one focused improvement with a regression
check, then report the change and test outcome. Work only in this worktree.
TASK

# New branches/worktrees are created through worktrunk, without its hooks.
# --yes approves sending this exact prompt to each worker.
bonsai fanout --branches retry-a,retry-b,retry-c \
  --prompt-file task.md --yes > workers.txt

while IFS= read -r pane; do
  bonsai wait --pane "$pane" --for done --timeout 20m || continue
  bonsai capture "$pane" -S -200 > "result-${pane#%}.txt"
done < workers.txt

# Read result-*.txt, then address one worker explicitly.
pane=$(head -n 1 workers.txt)
bonsai reply "$pane" 'Explain the tradeoff in the test you added.' --yes
```

`spawn --branch NAME` reuses an existing worktree or creates it with worktrunk. It starts a new session, or a new window when the session already exists; `--window` uses the current session. The command prints only the pane ID to stdout, so callers can capture it. Worktrunk progress and errors go to stderr. An agent runs above a surviving shell so its pane remains available after exit.

With a prompt, spawn waits up to 30 seconds for an idle/done/waiting hook or title state. If the CLI never reports readiness, it leaves the worker running, does not send the prompt, and exits 124. Inspect the pane and use `reply` once it is ready. `--agent` names an executable; put custom flags in a small executable wrapper. `--prompt` and `--prompt-file` are mutually exclusive.

`wait` accepts exactly one pane or branch selector. A branch wait succeeds when every matching agent is in the desired state. Supported states are `done`, `waiting`, `idle`, and `exited`; an idle agent also satisfies `done`. A missing pane satisfies `exited`. A missing branch keeps waiting until the timeout. Exit status is 0 on success, 124 on timeout, and 2 for invalid arguments. `--json` emits matching pane/state records, or an object with `error: "timeout"` and the last snapshot.

```bash
bonsai wait --branch retry-a --for waiting --timeout 5m --json
bonsai list --json | jq '.[] | {pane_id, branch, state, unseen, prompt, message}'
bonsai send --to @waiting 'Continue using the documented default.' --yes
bonsai send --to @branch:retry-a 'Run the focused test once more.' --yes
bonsai send --to @all 'Summarize your progress.' --yes
```

`list --json` returns an array. Records include pane/session/window IDs, location, agent, current and raw state, state/seen timestamps, age, unread flag, working directory, repository, branch, prompt, message, pending question, tool, session ID, model/context metadata, liveness, and resumability. `--branch NAME` and `--state STATE` filter it. `--counts` prints eight integers: waiting, error, working, unread done, all done, idle, exited, unknown. `--rows` is the board's internal eight-field unit-separated format.

`send` supports one pane, `@waiting`, `@idle`, `@all`, or `@branch:NAME`; it prints the selected destinations before asking for confirmation. `reply` and `send` both require confirmation unless `--yes` is supplied. Use `--no-enter` to type without submitting. To send text that starts with a flag, put `--` before the text:

```bash
bonsai reply %3 --yes --no-enter -- '--help'
```

`bonsai kill %3` confirms and sends Ctrl-C. `--pane` closes the pane after confirmation; `--yes` is available for automation. `bonsai resume %3` requires an exited agent with a recorded session ID, then confirms the appropriate `claude --resume`, `opencode --session`, or `codex resume` command. Neither command changes worktree files.

For a generic process, use `bonsai mark "$TMUX_PANE" working`, followed by `done` or `error`; `clear` removes its metadata. The collector, board, feed and notification pipeline then observe it just like an agent hook.
