# tmux-worktrunk

A self-contained tmux plugin for a git **worktree-per-task** workflow.
[worktrunk](https://worktrunk.dev) (`wt`) is the git engine; the plugin owns all the
tmux orchestration. **No worktrunk config / hooks required** — every `wt` call is made
with `--no-hooks --no-cd`, and the plugin creates the sessions, builds the window
layout, switches the client, and tears things down itself.

## Requirements

- tmux **>= 3.2** (`display-popup`)
- [worktrunk](https://worktrunk.dev) (`wt`) on `PATH`
- `git`, `awk`, `sed` (standard)
- `fzf` — for the "open / switch" picker
- `gh` (or `glab`) — for "open PR"
- your agent CLI (`claude`, `opencode`, ...) — for "new + agent"

That's it. No `~/.config/worktrunk/config.toml`, no shell functions.

## Install

### TPM
```tmux
set -g @plugin 'youruser/tmux-worktrunk'
run '~/.tmux/plugins/tpm/tpm'
```
`prefix + I` to fetch.

### Local / no TPM
```tmux
run-shell '~/code/tmux-worktrunk/worktrunk.tmux'
```
`tmux source-file ~/.tmux.conf` to reload.

## Use

`prefix + W` opens the menu:

| Key | Action |
|-----|--------|
| n | New worktree → own session with the window layout |
| a | New worktree + launch the agent in the `agent` window |
| o | Open / switch — fzf over worktrees **and** local/remote branches (with log preview) |
| p | Open a teammate's PR by number |
| w | New worktree as a **window** in the current session |
| l | Rebuild the layout in this session |
| r | Promote the current window-worktree into its own session |
| e/j/s | Jump to the edit / agent / serve window |
| L | List all worktrees (`wt list --full`) |
| N | Set up agent notifications (writes the Claude Code + opencode hooks) |
| c | Clear all agent markers |
| x | Remove the current worktree (auto-detects session vs window) |
| X | Remove every worktree whose branch is merged into the default branch |

The "open / switch" picker handles all three navigation cases in one place: an existing
worktree (jumps to its session), a local branch with no worktree yet, or a teammate's
remote branch (worktrunk checks it out into a fresh worktree, then the plugin builds the
session).

## Options

```tmux
set -g @worktrunk-key     'W'                  # menu key (under prefix)
set -g @worktrunk-agent   'claude'             # 'opencode', 'opencode run', ...
set -g @worktrunk-windows 'edit agent serve git'  # layout; first window is focused
set -g @worktrunk-notify  'on'                     # agent markers + focus-clear
```

If you rename the windows, update the `e/j/s` jump entries in `scripts/menu.sh` to match.

## How it stays config-free

| Step | Who does it |
|------|-------------|
| create branch + worktree, PR resolution, copy `.env`, remove + delete-if-merged | `wt` (`--no-hooks --no-cd`) |
| find the worktree path | `git worktree list --porcelain` |
| create session, build window layout, switch client, kill session/window | the plugin |

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
set -g @worktrunk-notify on
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
# in the agent window, e.g. add to layout creation:
setw monitor-silence 20
set -g @worktrunk-notify on
set-hook -ga alert-silence 'run-shell "~/.tmux/plugins/tmux-worktrunk/scripts/notify.sh done"'
```

Less precise (a long pause mid-task can false-trigger), but needs no agent support.

### Requirements for notifications

`jq` (to merge Claude Code settings), and `notify-send` (Linux: `apt install libnotify-bin`)
or `terminal-notifier`/`osascript` (macOS). Kitty users can swap in `kitten notify`.

## Optional: key-table instead of a menu

```tmux
bind -T worktree n display-popup -d "#{pane_current_path}" -E "~/code/tmux-worktrunk/scripts/new.sh"
bind -T worktree o display-popup -d "#{pane_current_path}" -E "~/code/tmux-worktrunk/scripts/switch.sh"
bind -T worktree x confirm-before -p "remove? (y/n) " "run-shell '~/code/tmux-worktrunk/scripts/remove.sh'"
bind w switch-client -T worktree
```

## Notes

- Teardown runs via `run-shell` (tmux server context), not inside the worktree's shell,
  so removing the session you're in is safe.
- `prune` uses a git-ancestor check — catches fast-forward/rebase merges, not squash.
  For squashed branches use `wt list --full` (dims safe-to-delete) and remove by hand.
- The fragile part of any tmux plugin is `display-menu` argument quoting; test each entry
  if you edit `scripts/menu.sh`.
