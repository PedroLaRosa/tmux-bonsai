# Bonsai Dashboard — cross-session worktree & agent jump board

## Context

`tmux-bonsai` is a lean (~400 LOC), **stateless** shell plugin: it derives all state
live from `git worktree list` + `tmux list-*`, and already has agent notifications —
agents call `scripts/notify.sh <waiting|done|error>` (via Claude Code hooks /
an opencode plugin), which sets a **per-window** option `@agent_state` and fires a
desktop alert. There is a status-line glyph and a plain-text `L → wt list --full`,
but **no aggregated, cross-session view** to see every worktree's agent state at a
glance and jump straight to whichever needs attention.

This change adds that: a **summon-on-demand, live-refreshing popup dashboard** listing
every worktree (live + offline) and every running agent with its state, where a single
keypress jumps you to the exact session / window / pane — across sessions and windows.

### Decisions locked with the user
- **Form factor:** live-refresh popup that snapshots on open, refreshes while open, dies
  on close. No background daemon — stays true to bonsai's no-state ethos.
- **Granularity:** **per-pane.** `@agent_state` moves from window scope to pane scope so
  each split-pane agent is its own row + jump target.
- **Scope:** **live + offline.** Cross-reference `git worktree list`; worktrees with no
  live session show as `⏸ offline` and re-open on selection via `wt_ensure_session`.
- **New `working` state:** track actively-running agents (🔄), not just waiting/done/error.

### State model
| state | glyph | set by | desktop alert? |
|-------|-------|--------|----------------|
| working | 🔄 | Claude `UserPromptSubmit` / opencode start event | no (mark only) |
| waiting | 💬 | Claude `Notification` | yes |
| done | ✅ | Claude `Stop` / opencode `session.idle` | yes |
| error | ❗ | opencode `session.error` | yes |
| idle | — | (live session, no agent event yet) | — |
| offline | ⏸ | derived from git (no live session) | — |

## Files to change

### `scripts/notify.sh` — per-pane + `working` + timestamp
- Set state on the **pane** (source of truth): `tmux set-option -p -t "$pane" @agent_state "$state"`
  and `tmux set-option -p -t "$pane" @agent_state_ts "$(date +%s)"`.
- Keep a coarse **window mirror** (`set-option -w -t "$win" @agent_state "$state"`) so the
  existing optional status-line glyph keeps working for single-agent windows (documented as coarse).
- Recompute the "am I already looking at it" suppression at pane scope: query
  `#{pane_active}|#{window_active}|#{session_attached}` — suppress desktop alert only when all true.
- `working` is **mark-only**: set the markers, then `exit 0` before the desktop-notify block
  (avoids alert spam on every turn). Add `working` to the `case`.

### `bonsai.tmux` — pane-scoped focus-clear + dashboard binding
- Change the focus hook to clear the pane option (and the coarse window mirror):
  `set-hook -ga pane-focus-in 'set-option -pu @agent_state ; set-option -pu @agent_state_ts ; set-option -wu @agent_state'`
  (verify the hook's current-pane context resolves the focused pane; this is the standard pattern).
- Add an **opt-in direct keybinding** (documented, default unset to avoid grabbing a key):
  `dkey=$(tmux show-option -gqv @bonsai-dashboard-key); [ -n "$dkey" ] && tmux bind-key "$dkey" run-shell "$CURRENT_DIR/scripts/launch.sh dashboard.sh"`.

### `scripts/clear-markers.sh` — clear per-pane
- Iterate panes instead of windows: `tmux list-panes -a -F '#{pane_id}'` → `set-option -pu -t "$p" @agent_state` (+ `@agent_state_ts`), and still clear window mirrors.

### `scripts/install-notify.sh` — wire the `working` event
- **Claude Code:** add a `UserPromptSubmit` hook to the `jq` merge → `notify.sh working`.
- **opencode:** extend the plugin's event map with the "started/processing" event → `working`
  (verify the exact opencode event name against the plugin API; unmapped events stay no-ops, so it degrades gracefully).

### `scripts/menu.sh` — surface the dashboard
- Add an entry near "list worktrees", e.g.:
  `"dashboard (jump board)" d "run-shell -b '$S/launch.sh dashboard.sh'"`.
  Keep `list.sh` as the raw `wt list --full` view.

### NEW `scripts/dashboard.sh` — the live-refresh jump board
Launched through the existing popup wrapper (`launch.sh dashboard.sh`), exactly like
`switch.sh`/`list.sh`. Proven pattern: `switch.sh` already calls `switch-client` from
inside a bonsai popup, so navigation from the dashboard works the same way.

**Render-loop TUI (single-key select, no fzf, no daemon)** — mirrors `menu.sh`'s single-key idiom and keeps it lean (~70 lines):
```
refresh=$(tmux show-option -gqv @bonsai-refresh); refresh=${refresh:-2}
loop:
  rows=$(gather)            # build + sort rows (below)
  clear; render header + each row with a single-key label (1-9, a-z; skip r/q)
  read -t "$refresh" -rsn1 k   # timeout → live refresh
  case k in
    <label>) resolve target → jump (tmux nav) → exit 0   # popup closes, nav applies
    r)       continue                                    # refresh now
    q|ESC)   wt_back                                      # back to the menu
    "")      continue                                    # timed out → re-render
  esac
```

**`gather` — enumerate rows (pure live derivation):**
1. **Agent panes (precise):** `tmux list-panes -a -F '#{pane_id}\t#{session_name}\t#{window_id}\t#{window_name}\t#{pane_current_path}\t#{@agent_state}\t#{@agent_state_ts}'`; keep rows where `@agent_state` is non-empty → one row each.
2. **Worktrees (from git):** parse `git worktree list --porcelain` into (branch, path); `name = wt_sanitize(branch)` (reuse `_lib.sh`). For each worktree **without** an agent-pane row already: if a live session/window named `name` exists → `— idle` (live) row; else → `⏸ offline` row.
3. Match a pane to its worktree by `session_name`/`window_name == wt_sanitize(branch)` (bonsai names them exactly), with `pane_current_path` under the worktree path as fallback.

**Columns:** `<label>  <glyph> <state>  <worktree>  <where>  <age>`
- `where` ∈ `[sess]` / `[win]` / `[pane]` / `[git]`.
- `age` = `now - @agent_state_ts` rendered `5s`/`2m`/`1h`; `—` for idle/offline.
- **Sort priority** (default, tweakable constant): waiting → error → done → working → idle → offline.

**Jump resolution** by target kind (follow `switch.sh`):
- pane → `tmux select-window -t <window_id>; tmux select-pane -t <pane_id>; tmux switch-client -t <session>`
- live session-worktree → `tmux switch-client -t <session>`
- live window-worktree → `tmux select-window -t <window_id>; tmux switch-client -t <session>`
- offline → `path=$(wt_path_of "$branch")`; `S=$(wt_ensure_session "$branch" "$path")`; `tmux switch-client -t "$S"` (reuses `_lib.sh`).

### `README.md`
- Document the dashboard (menu entry + optional `@bonsai-dashboard-key`), the new `working`
  state, the per-pane tracking change, `@bonsai-refresh`, and note the status-line glyph is now
  a coarse single-agent-window rollup (the dashboard is the precise per-pane surface).

## Reuse
- `_lib.sh`: `wt_sanitize`, `wt_path_of`, `wt_ensure_session`, `wt_agent`, `wt_back`.
- `launch.sh` popup wrapper + `@bonsai-back` menu re-entry — no new popup machinery.
- `switch.sh`'s switch-client-from-popup pattern for jumping.

## Verification (end-to-end in tmux, test on macOS/BSD)
1. Re-source plugin; run **setup notifications** (`N`) to wire the new `working` hook; `set -g @bonsai-notify on`.
2. Create worktrees: one session-worktree + agent, one window-worktree + agent, one split-pane agent (so a single window holds two agent panes — the per-pane case).
3. Drive states: submit a prompt (→ 🔄 working), let it ask for input (→ 💬 waiting), let it finish (→ ✅ done). Kill one session to leave a `⏸ offline` worktree.
4. Open the dashboard (menu `d`, or the direct key). Confirm:
   - one row **per agent pane** with the correct glyph (the two split agents show distinct states — the per-pane payoff);
   - the offline worktree appears as `⏸ offline`;
   - **live refresh**: a working→done transition appears within `@bonsai-refresh` seconds without reopening;
   - pressing a label jumps to the **exact** session/window/pane; `r` refreshes; `q`/esc returns to the menu.
5. Focus a flagged pane → its marker clears (pane-scoped) and it drops off the attention list.
6. `clear agent markers` (`c`) clears every pane.
7. Smoke-test both agents if available (Claude via hooks; opencode `working` event — confirm the event name, accept graceful no-op if absent).
