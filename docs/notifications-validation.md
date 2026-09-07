# Notification and board implementation validation

The P0–P5 implementation is in this branch: socket-aware state, settings and
CLI; notification backends and verification; the live board and activity feed;
provider adapters and title/bell evidence; and orchestration/resume commands.

## Automated coverage

Run `bash tests/run.sh` on a private tmux server. The suites cover:

- Adapter config preservation, backups, repair, malformed input, provider
  payloads, optional statusline integration, source ordering and pipe detachment.
- Pane state transitions, timestamps, out-of-order events, concurrent writes,
  subagents, title precedence, native/notify-only Codex evidence, Gemini waits,
  window mirrors, acknowledgement and focus reporting.
- Notification gates, privacy, literal command-backend environment, stale
  workers, metadata-preserving generations, cooldown races, reminders, real PTY
  focus changes, and gone panes.
- Collector ordering, escaping, counts, liveness, real fzf listeners, socket
  isolation, reply guards, worktree spawn/fanout, wait timeouts, hydrated feed
  records and notification-click terminal selection.
- Plugin reloads, preserving user hooks, settings precedence, quoted paths,
  recursive installation and the optional CLI symlink.

The harness uses Bash assertions instead of adding a Bats dependency. CI runs
syntax checks, ShellCheck, and these suites on Ubuntu and macOS. No real agent
account, desktop permission change, or push-service credential is needed.
Targeted state, path and raw-capture checks also passed with an actual tmux 3.4
build on macOS; the installer regression explicitly invokes stock `/bin/bash`.

## Measured performance

On the implementation machine (macOS, Bash 5.3, tmux 3.6a, fzf 0.72):

| Measurement | Observation |
| --- | --- |
| 30 mixed panes, warm collector median | 102 ms |
| Collector cold / warm maximum | 135 ms / 143 ms |
| Live fzf push refresh visible | 291 ms |
| Foreground hook, 40 launches with 4 KB payload | median 7.32 ms; p95 9.06 ms |
| Foreground hook cold maximum | 125.17 ms |
| Inherited stdout/stderr EOF | Returned before a detached two-second reducer finished |

These are measurements, not guarantees. The final run did not meet the plan's
100 ms collector and 200 ms push targets; earlier runs reached 97 ms and
123 ms, respectively, but those are not sustained performance guarantees.
`bash tests/latency.sh` reports timing without treating scheduler variability
as a CI failure. Run
`bash tests/manual/board-capture.sh` to reproduce the board measurement and
regenerate its actual terminal capture. The plan's more ambitious 40-pane/60 ms
collector budget is not established by the 30-pane result.

## Intentional implementation adjustments

- `@agent_seq` orders accepted events; `@agent_generation` tracks meaningful
  state/turn changes. Metadata must not cancel pending completion notifications.
- Action-listener backends log `queued`, then eventual `delivered` or `failed`.
  Only the interactive test establishes that an OS banner was visible.
- Current official Copilot and Droid config locations/shapes supersede the
  proposed paths. Codex native hooks require explicit trust review in `/hooks`;
  bonsai never grants trust. See [provider details](hooks.md).
- Listener registries, focus evidence and cycling cursors are scoped to the
  originating tmux socket.
- Live refresh requires fzf 0.40 for dynamic headers; earlier versions retain
  manual reload. Cursor tracking is enabled from fzf 0.39.

## Manual checks

The [notification guide](notifications.md#migration-and-manual-verification) contains the
remaining desktop/terminal matrix. Real macOS/Linux/WSL banner permissions,
Do Not Disturb, sound behavior, SSH/OSC delivery, and click activation across
terminal applications require testing in those environments. Automated tests
use a recording command backend and fixture agents. No personal agent settings
were installed or modified while implementing this plan.
