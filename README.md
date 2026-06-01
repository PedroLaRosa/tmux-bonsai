# 🌳 tmux-bonsai

> Cultivate parallel git worktrees and AI agents across branches — without leaving tmux.

**tmux-bonsai** turns your tmux server into a workbench for a git **worktree-per-task**
workflow. Spin up an isolated worktree for any branch, drop it into its own tmux session,
and launch an AI coding agent (Claude Code, opencode, …) right where the work lives — then
get pinged the moment any agent in any session finishes or needs input. Jump between tasks
with a single `fzf` picker, and promote a scratch window into its own session. Like tending
a bonsai: many small branches, each shaped deliberately, all in view at once.

Bring your own layout: bonsai never enforces one — shape each session with a separate
plugin (tmuxinator, smug) or a tmux `session-created` hook (see [Layout](#layout)).

<p align="center">
  <img src="docs/menu.png" alt="tmux-bonsai menu (prefix + W): Session, Window, Notify and Remove actions" width="640">
</p>

[worktrunk](https://worktrunk.dev) (`wt`) is the git engine; the plugin owns all the
tmux orchestration. **No worktrunk config / hooks required** — every `wt` call is made
with `--no-hooks --no-cd`, and the plugin creates the session, switches the client, and
tears things down itself.

## Requirements

- tmux **>= 3.2** (`display-popup`)
- [worktrunk](https://worktrunk.dev) (`wt`) on `PATH`
- `git`, `awk`, `sed` (standard)
- `fzf` — for the "open / switch" picker
- your agent CLI (`claude`, `opencode`, ...) — for "new + agent"

That's it. No `~/.config/worktrunk/config.toml`, no shell functions.

## Install

### TPM
```tmux
set -g @plugin 'PedroLaRosa/tmux-bonsai'
run '~/.tmux/plugins/tpm/tpm'   # keep this last — @plugin lines go above it
```
`prefix + I` to fetch. No clone needed; TPM installs into `~/.tmux/plugins/tmux-bonsai/`.

Pin a release instead of tracking the default branch:
```tmux
set -g @plugin 'PedroLaRosa/tmux-bonsai#v1.0.0'
```

### Local / no TPM
```tmux
run-shell '~/code/tmux-bonsai/bonsai.tmux'
```
`tmux source-file ~/.tmux.conf` to reload.

## Use

`prefix + W` opens the menu:

| Key | Action |
|-----|--------|
| n | New worktree → its own session |
| a | New worktree + launch the agent in that session |
| o | Open / switch — fzf over worktrees **and** local/remote branches (with log preview) |
| w | New worktree as a **window** in the current session |
| r | Promote the current window-worktree into its own session |
| L | List all worktrees (`wt list --full`) |
| N | Set up agent notifications (writes the Claude Code + opencode hooks) |
| c | Clear all agent markers |
| x | Remove the current worktree (auto-detects session vs window) |

The "open / switch" picker handles all three navigation cases in one place: an existing
worktree (jumps to its session), a local branch with no worktree yet, or a teammate's
remote branch (worktrunk checks it out into a fresh worktree, then the plugin builds the
session).

## Options

```tmux
set -g @bonsai-key    'W'        # menu key (under prefix)
set -g @bonsai-agent  'claude'   # 'opencode', 'opencode run', ...
set -g @bonsai-notify 'on'       # agent markers + focus-clear
```

## Layout

bonsai creates a **bare single-window session** at the worktree path and switches to it —
nothing more. Shape it however you like; bonsai never overrides your choice:

```tmux
# example: split every new session into editor + side terminal
set-hook -g session-created 'split-window -h ; select-pane -L'
```

For richer, per-project layouts use a dedicated tool like
[tmuxinator](https://github.com/tmuxinator/tmuxinator) or
[smug](https://github.com/ivaaaan/smug).

## How it stays config-free

| Step | Who does it |
|------|-------------|
| create branch + worktree, copy `.env`, remove | `wt` (`--no-hooks --no-cd`) |
| find the worktree path | `git worktree list --porcelain` |
| create session, switch client, kill session/window | the plugin |

So worktrunk never needs to know about tmux, and tmux never needs a worktrunk config file.


## Agent notifications

Get alerted when an agent in **any** pane/window/session finishes or needs input.
Two layers:

### Layer 1 — agent-native hooks (precise)

Run **`prefix + W` -> "setup notifications"** (or `scripts/install-notify.sh` directly).
It wires both agents to `scripts/notify.sh`:

- **Claude Code** -> merges into `~/.claude/settings.json`:
  `Stop` hook -> `notify.sh done`, `Notification` hook -> `notify.sh waiting`.
- **opencode** -> drops an auto-loaded plugin at `~/.config/opencode/plugin/wt-notify.js`
  that maps `session.idle` -> done and `session.error` -> error.
  (If your opencode version loads from `plugins/` instead of `plugin/`, move the file.)

`notify.sh` runs inside the agent's pane (`$TMUX_PANE`), so it:

1. Marks that window with `@agent_state` = `waiting` / `done` / `error`.
2. Fires a desktop notification **only if you aren't already looking at that window**
   (`notify-send` on Linux, `terminal-notifier`/`osascript` on macOS).

Then enable the tmux side and reload:

```tmux
set -g @bonsai-notify on
```

This turns on `focus-events` and clears a window's marker the moment you focus it.

Optional status-line marker (adapt into your theme — it reads `@agent_state` per window):

```tmux
set -g window-status-format '#I:#W#{?#{!=:#{@agent_state},}, #{?#{==:#{@agent_state},waiting},💬,#{?#{==:#{@agent_state},error},❗,✅}},}'
```

### Layer 2 — tmux fallback (universal)

For any agent without hooks, monitor the agent pane for output silence and route the
native alert through the same marker:

```tmux
# in the agent's pane/window:
setw monitor-silence 20
set -g @bonsai-notify on
set-hook -ga alert-silence 'run-shell "~/.tmux/plugins/tmux-bonsai/scripts/notify.sh done"'
```

Less precise (a long pause mid-task can false-trigger), but needs no agent support.

### Requirements for notifications

`jq` (to merge Claude Code settings), and `notify-send` (Linux: `apt install libnotify-bin`)
or `terminal-notifier`/`osascript` (macOS). Kitty users can swap in `kitten notify`.

## Optional: key-table instead of a menu

```tmux
bind -T worktree n display-popup -d "#{pane_current_path}" -E "~/code/tmux-bonsai/scripts/new.sh"
bind -T worktree o display-popup -d "#{pane_current_path}" -E "~/code/tmux-bonsai/scripts/switch.sh"
bind -T worktree x confirm-before -p "remove? (y/n) " "run-shell '~/code/tmux-bonsai/scripts/remove.sh'"
bind w switch-client -T worktree
```

## Notes

- Teardown runs via `run-shell` (tmux server context), not inside the worktree's shell,
  so removing the session you're in is safe.
- The fragile part of any tmux plugin is `display-menu` argument quoting; test each entry
  if you edit `scripts/menu.sh`.
