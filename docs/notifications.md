# Notifications

Open `prefix + W` → **Notifications** to enable categories, choose a backend,
adjust sounds, install agent hooks, or run the notification test. For CLI setup:

```sh
bonsai hooks install claude
bonsai notify test
bonsai notify status
bonsai doctor
```

See [hook setup](hooks.md) for provider paths, optional Codex native hooks, trust,
and safe repair/removal. Notification settings do not install agent hooks until
you select an agent in Setup or run `hooks install`.

## Verify what appears

`bonsai notify test` sends through the selected real backend and asks whether a
banner appeared. It bypasses the master/category switches, focus suppression,
cooldown, and completion delay. Results are stored as:

| Outcome | Meaning |
| --- | --- |
| `verified` | The backend accepted the request and you confirmed seeing a banner. |
| `not-displayed` | The request was accepted, but you did not confirm seeing a banner. |
| `not-sent` | No backend accepted the request. |

Evidence includes the timestamp and backend in `notify-verify` under Bonsai's
state directory. A successful tool exit is not proof that the OS displayed a
banner. Test again after changing backends or notification permissions. With
multiple backends, verification concerns the combined test; it does not certify
every destination separately. Test notification clicks separately by switching
panes and clicking **Jump** where available.

On macOS, allow notifications for **terminal-notifier** when using that backend,
or **Script Editor** when using `osascript`. These are distinct permission
identities. `bonsai open-settings` opens the relevant preferences when possible;
over SSH it prints local-machine guidance. The doctor reports dependencies,
effective PATH, focus evidence, hooks, backend availability, test evidence, and
available best-effort Do Not Disturb probes.

## Delivery rules

Normal notifications pass the master switch, category switch, focus check,
per-pane cooldown, and completion grace window before delivery. A completion
followed by renewed work during the grace window is cancelled. Codex permission
requests receive an additional short debounce. Delivery rechecks state and focus
after the delay so stale work cannot announce a new turn as finished.

`strict` focus mode suppresses banners only for the active pane of a client that
has reported terminal focus. Enable tmux `focus-events on` through Setup and
focus your terminal once. If focus reports are unavailable, choose `attached`
to suppress visible active panes in attached clients, or `off` to always notify.
Suppression acknowledges the pane. Selecting a pane also acknowledges it,
dismisses supported banners, and cancels pending reminders.

An unseen input request can receive one delayed reminder. Acknowledgement or a
new state invalidates it. Terminal bells are off by default; opt in if useful.
Recent hook evidence suppresses duplicate bell notifications during cooldown.
`bonsai watch-silence WINDOW SECONDS` enables tmux silence evidence for a window.

Use `bonsai feed` or `bonsai feed --json` to inspect decisions such as `disabled`,
`category-off`, `suppressed-focus`, `cooldown`, `grace-cancelled`, `backend-missing`,
`failed`, `queued`, and `delivered`. Here `delivered` means backend request handling
succeeded; use the interactive test to establish visible OS delivery. Action
listeners run detached: `queued` records their launch, then the listener records its eventual success or failure.

## Settings

Use `bonsai settings set NAME VALUE`, or place `set -g @bonsai-NAME VALUE` in
tmux.conf. Menu settings persist in `${XDG_CONFIG_HOME:-~/.config}/tmux-bonsai/settings.tmux`.
Explicit tmux.conf options are intended to remain authoritative. Durations
accept seconds, including fractions such as `0.5`, or units such as `10m` and `6h`.

| Setting name | Default | Purpose |
| --- | --- | --- |
| `notify` | `on` | Master desktop/terminal notification switch. State tracking remains active. |
| `notify-finished`, `notify-input`, `notify-error` | `on` | Finished, needs-input, and error categories. |
| `notify-on-bell` | `off` | Convert terminal bells into notifications. |
| `notify-focus` | `strict` | `strict`, `attached`, or `off`. |
| `notify-cooldown` | `5` | Minimum gap per pane between deliveries. |
| `notify-grace` | `1.5` | Quiet window before completion delivery. |
| `notify-remind` | `10m` | One reminder for an unseen waiting pane; `off` disables. |
| `notify-preview` | `on` | Include a bounded prompt/answer/question preview in OS banners. |
| `notify-backend` | `auto` | Backend name or comma-separated destinations. |
| `notify-command` | empty | Executable file for the `command` backend. |
| `sound-mode` | `system` | `system`, `bell`, `both`, or `off`. |
| `sound-finished`, `sound-input`, `sound-error` | platform defaults | Backend sound names; stopped turns are silent. |
| `terminal` | `auto` | Terminal identity override where supported. |
| `status`, `window-glyphs` | `off` | Optional status counts and window state decoration. Reload the plugin after changing. |

macOS defaults are `Glass`, `Ping`, and `Basso`. Linux defaults are
`message-new-instant`, `dialog-information`, and `dialog-error`. Backend/daemon
sound support varies. Bell mode writes a terminal bell to attached clients.

```sh
bonsai settings set notify-focus attached
bonsai settings set notify-preview off
bonsai settings set notify-backend terminal-notifier,command
bonsai settings set notify-remind off
```

## Backends and limitations

`auto` prefers macOS `terminal-notifier` → `alerter` → `osascript`, or Linux
`notify-send` → `dunstify` → `gdbus` when a desktop environment is present. Over
SSH, and when no local desktop backend is available, recognized terminals can use
OSC. With no usable backend, the status/feed report that delivery is unavailable.

| Backend | Replacement/dismissal | Click behavior |
| --- | --- | --- |
| `terminal-notifier` | Stable pane group; dismissed on acknowledgement. | Exact tmux pane plus terminal activation where identified. |
| `alerter` | Stable group replaces; action waiter times out after 30 seconds. | Jump action or banner contents selects the pane. |
| `osascript` | No pane replacement or programmatic dismissal. | No tmux jump; macOS opens its notification application. |
| `notify-send` | Uses IDs when supported; old versions degrade. Dismissal can use D-Bus. | `--wait`/actions when supported. |
| `dunstify` | Notification IDs; `-C` dismisses. | Jump action selects the pane. |
| `gdbus` | D-Bus replace ID and close notification. | No action listener. |
| `osc` | kitty OSC 99 uses stable IDs; OSC 777/9 are terminal-dependent. | Terminal focus where supported; no exact tmux pane jump. |
| `command` | Your executable implements delivery/replacement. | Your executable chooses its action behavior. |
| `none` | No backend selected. | None. |

OSC requires tmux 3.3+ and `allow-passthrough all` to reach hidden panes. Bonsai
selects OSC 99 for kitty, OSC 777 for WezTerm/foot/Ghostty, and OSC 9 for iTerm.
Local terminal notification settings still apply. With mixed terminal types
attached to one server, the shared terminal detection may not suit every client.
Desktop focus/activation is best-effort, particularly on Wayland.

For the command backend, configure an executable path, not a shell expression:

```sh
bonsai settings set notify-command "$HOME/.local/bin/my-bonsai-notify"
bonsai settings set notify-backend command
```

The command receives `BONSAI_CATEGORY`, `BONSAI_TITLE`, `BONSAI_BODY`,
`BONSAI_SUBTITLE`, `BONSAI_PANE`, `BONSAI_SESSION`, `BONSAI_WINDOW`,
`BONSAI_WINDOW_NAME`, `BONSAI_AGENT`, `BONSAI_STATE`, `BONSAI_BRANCH`,
`BONSAI_REPO`, `BONSAI_CWD`, `BONSAI_ID`, `BONSAI_SOUND`, `BONSAI_SOCKET`, and
`BONSAI_JUMP_CMD`. Keep credentials in your executable's environment or private
configuration. `BONSAI_ID` is stable per pane. A relay such as ntfy, Pushover,
Telegram, or a webhook can be implemented in this command; Bonsai does not create
a relay or contact these services itself.

## Migration and manual verification

Existing status snippets reading `@agent_state` and `@agent_state_ts` continue to
work. After configuring Bonsai hooks, remove the companion `tmux-agent-notify`
plugin and only its managed agent hook entries to prevent duplicate notifications.
The doctor detects common companion leftovers. It does not remove user config
automatically. Re-run `hooks install` after moving your plugin checkout.

Automated tests exercise notification gates and state changes using a private
tmux server and a recording command backend. They do not establish OS permission,
desktop banner visibility, sound playback, or terminal focus behavior. Complete
the applicable manual checks on each machine:

| Environment | Manual check |
| --- | --- |
| macOS + terminal-notifier | Allow banners for terminal-notifier; verify one visible banner, sound, replacement, Jump, and dismissal on acknowledgement. |
| macOS + osascript | Allow Script Editor; verify banner and sound; expect no pane click routing. |
| Linux GNOME/KDE/XFCE | Run a test with the available backend, verify daemon banner permissions/DND, sound, and supported Jump actions. |
| dunst/mako | Inspect paused/DND mode; test replacement and any available actions. |
| SSH + kitty/WezTerm/Ghostty/foot/iTerm | Enable local terminal notifications and tmux passthrough; test a hidden pane and focus behavior. |
| WSL | Check Windows notification preferences and terminal OSC support; native Windows execution is outside this plugin's scope. |

The feed is JSONL in `${XDG_STATE_HOME:-~/.local/state}/tmux-bonsai/events.jsonl`
unless `@bonsai-state-dir` overrides it. It is private (`0600`), bounded and
rotated, and contains preview text. Disabling desktop previews does not erase
the pane's previews or historical feed. Clear markers through the menu when
you want to remove pane state.
