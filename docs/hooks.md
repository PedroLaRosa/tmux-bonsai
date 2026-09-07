# Agent hook setup

Run `bonsai hooks status`, then install the agents you use:

```sh
bonsai hooks install claude opencode codex
bonsai hooks explain claude
bonsai hooks remove claude
```

The Notifications setup wizard performs the same operations. Installation
requires `jq`. It skips an agent whose CLI is missing. For advance configuration,
call its adapter directly: `scripts/adapters/claude.sh install --force`.

Installers back up changed files as `.bak-<epoch>-<pid>`, write a private temporary
file in the same directory, then atomically replace the original. JSON must
validate before replacement. Reinstalling repairs missing entries and old plugin
paths. Removing hooks preserves user hooks, including other handlers in the same
matcher group. Existing unrelated Codex `notify` or Claude `statusLine` commands
are preserved and reported as conflicts. Symlinked configs require an explicit
`BONSAI_ADAPTER_CONFIG=/absolute/target` override.

`installed` describes the configuration on disk. Agent policy, disabled hooks,
version differences, and Codex trust can still prevent execution. `partial` means
the expected entries differ or a plugin path has moved. `bonsai doctor` and
`bonsai feed` help distinguish missing hook evidence from notification suppression.

## Supported providers

The schemas below were checked against the linked primary documentation on
2026-09-07. They correct a few paths and schema assumptions in the original plan.

| Adapter | Configuration | Coverage |
| --- | --- | --- |
| `claude` | `~/.claude/settings.json` | Session, prompt, tool, permission, notification, stop/failure, subagent, and manual compaction events. |
| `opencode` | `${XDG_CONFIG_HOME:-~/.config}/opencode/plugins/tmux-bonsai.js` | Directory plugin; root-session lifecycle, child roster/waits, and prompt/answer previews. |
| `codex` | `${CODEX_HOME:-~/.codex}/config.toml` | Stable `notify` command for completed turns. Titles supply working evidence. |
| `codex-hooks` | `${CODEX_HOME:-~/.codex}/hooks.json` | Optional native lifecycle, permission, interruption, compaction, and subagent hooks; requires review in Codex. |
| `gemini` | `~/.gemini/settings.json` | Before/after agent and tool events. Titles supply waiting evidence. |
| `cursor` | `~/.cursor/hooks.json` | Prompt, tool, shell/MCP, answer, and stop events with neutral JSON responses. |
| `copilot` | `${COPILOT_HOME:-~/.copilot}/hooks/tmux-bonsai.json` | Current CLI user-hook directory with PascalCase events and snake_case input fields. |
| `droid` | `~/.factory/hooks.json` | Unwrapped event map; lifecycle, tools, subagent stop, and notification waits. Existing legacy settings hooks migrate into this file. |
| `claude-statusline` | `~/.claude/settings.json` | Optional silent usage adapter for pane model/context fields. |

`CLAUDE_CONFIG_DIR` is honored for Claude's settings location. Set tmux option
`@bonsai-hooks-tool-events off` before reinstalling to omit per-tool hooks. A
single adapter can also be configured with `install --tools off`.
Claude's own terminal bell is opt-in:
`scripts/adapters/claude.sh install --terminal-bell` merges
`preferredNotifChannel: "terminal_bell"` in the same backed-up transaction.

The [Claude hook reference](https://code.claude.com/docs/en/hooks) documents the
nested matcher/handler schema. Hooks emit no decisions; background Claude jobs
with `CLAUDE_JOB_DIR` are ignored. The optional
[statusLine adapter](https://code.claude.com/docs/en/statusline) is silent: it feeds
the board without rendering a Claude status line. Install it explicitly with
`bonsai hooks install claude-statusline`. If you already render a status line,
feed the same JSON to `scripts/hooks/hook-claude-statusline.sh` from that script.

The [OpenCode directory plugin API](https://opencode.ai/docs/plugins/) uses a named
async factory. Bonsai exports only that factory: exporting an additional object
would break loaders that call every export. Session ancestry is cached and looked
up through the provider client when missing; unresolved ancestry is ignored.
Child completions update the roster without completing the parent. Assistant
previews are throttled to one per second and the latest text accompanies idle.
This targets the documented directory plugin API, not a separate v2 package API.

The [Gemini reference](https://geminicli.com/docs/hooks/reference/) uses milliseconds
for command timeouts, unlike Claude's seconds. The
[Cursor reference](https://cursor.com/docs/hooks) accepts hook responses; Bonsai
returns `{"continue":true}` for prompt submission and `{}` for other events.
It never grants permission. CLI event coverage can differ by version.

The [Copilot reference](https://docs.github.com/en/copilot/reference/hooks-reference)
now documents user-level `hooks/*.json`; the plan's standalone
`~/.copilot/hooks.json` location is not used. Older versions may need an upgrade.
The [Factory reference](https://docs.factory.ai/harness/hooks) gives `hooks.json`
precedence over settings hooks, and its root is the event map itself. Factory's
documented permission signal is `Notification(permission_prompt)`;
`PermissionRequest` is not registered speculatively.

## Codex trust and existing commands

`bonsai hooks install codex` only adds a bounded top-level `notify` block to TOML.
It refuses an existing user `notify` assignment and refuses edited or unbalanced
managed markers. It does not rewrite arbitrary TOML tables. The
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
documents `notify` as an external command receiving a JSON payload.

For native lifecycle tracking, run:

```sh
bonsai hooks install codex-hooks
```

Then open `/hooks` in Codex and review/trust the installed commands. The current
[Codex hooks documentation](https://learn.chatgpt.com/docs/hooks) says hooks are
enabled by default and trust is tied to each exact definition. Changed commands
need review again. Bonsai writes only `hooks.json`; it never fabricates trust
hashes, enables disabled policy, or passes a trust-bypass flag. The installer
cannot certify runtime trust and says so in its status detail. Older Codex builds
can continue using `notify` alone.

## Execution and privacy

Hooks outside tmux exit successfully without creating state. Inside tmux they
read JSON, timestamp source order using Bash 5's clock or Perl's `Time::HiRes`, and
detach the reducer with inherited stdin/stdout/stderr closed. The detached
process uses `setsid` when available and `nohup` otherwise. JSON parsing and tmux
work occur after detachment; foreground hooks never invoke `jq`. Without Perl,
on Bash 3.2, the reducer still serializes events, but cannot reject reordered source events
using the hook timestamp.

The original sub-10 ms foreground goal is a target, not a portable timing
guarantee. After removing Perl import overhead, `bash tests/latency.sh` measured
6.3 ms median and 8.9 ms p95 over 40 macOS launches, with a 115 ms cold-start
outlier. Agent work and JSON parsing remain detached regardless of scheduler or
interpreter startup time. The benchmark also checks that inherited pipes close
while the reducer continues running.

Prompt text travels through an internal pipe, never shell evaluation or a
temporary prompt file. The board stores bounded previews in tmux pane options.
Set `@bonsai-notify-preview off` to omit preview text from desktop notifications.
