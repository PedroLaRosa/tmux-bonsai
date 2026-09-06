# Agent notifications

Install Claude Code hooks with `scripts/bonsai hooks install`, then restart Claude Code.
The installer backs up `~/.claude/settings.json` before writing managed hooks. Use
`hooks status`, `hooks explain`, or `hooks remove` to inspect and reverse the change.

Agent state is stored in pane options (`@agent_state`, `@agent_state_ts`,
`@agent_type`, `@agent_msg`, and `@agent_unread`) and disappears when the pane does.
Use `scripts/bonsai mark "$TMUX_PANE" waiting "question"` with another agent.

## Delivery

The `auto` backend selects `terminal-notifier` or `alerter` on macOS and `notify-send`
or `dunstify` on Linux. Set `@bonsai-notify-backend none` to retain tracking without
banners, or `command` with `@bonsai-notify-command` for a custom push service. The
command receives `BONSAI_CATEGORY`, `BONSAI_TITLE`, `BONSAI_BODY`, and `BONSAI_PANE`.

Notifications are suppressed while their pane is focused by default. Run
`scripts/bonsai notify test "$TMUX_PANE" test "hello"` and `scripts/bonsai doctor` when
diagnosing delivery.
