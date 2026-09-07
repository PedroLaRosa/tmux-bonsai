#!/usr/bin/env bash
source "$(dirname "$0")/helper.sh"
setup_test
unset CODEX_HOME CLAUDE_CONFIG_DIR COPILOT_HOME
export BONSAI_HOOKS_TOOL_EVENTS=on
ADAPTERS="$TEST_ROOT/scripts/adapters"

# Install/repair/remove preserve siblings, user metadata and permissions.
for provider in claude gemini cursor copilot droid codex-hooks; do
    export BONSAI_ADAPTER_CONFIG="$TMP/$provider.json"
    if [ "$provider" = droid ]; then
        printf '%s\n' '{"Stop":[{"matcher":"user","hooks":[{"type":"command","command":"echo mine"}]}]}' > "$BONSAI_ADAPTER_CONFIG"
    else
        printf '%s\n' '{"custom":{"keep":true},"hooks":{"Stop":[{"matcher":"user","hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$BONSAI_ADAPTER_CONFIG"
    fi
    assert_contains "$("$ADAPTERS/$provider.sh" install --force)" installed
    first=$(cat "$BONSAI_ADAPTER_CONFIG")
    assert_contains "$first" 'echo mine'
    "$ADAPTERS/$provider.sh" install --force >/dev/null
    assert_eq "$first" "$(cat "$BONSAI_ADAPTER_CONFIG")" "$provider idempotent"
    assert_contains "$("$ADAPTERS/$provider.sh" status)" installed
    # Reordering JSON keys must not be mistaken for hook drift.
    jq -S . "$BONSAI_ADAPTER_CONFIG" > "$TMP/sorted"
    cp "$TMP/sorted" "$BONSAI_ADAPTER_CONFIG"
    assert_contains "$("$ADAPTERS/$provider.sh" status)" installed
    "$ADAPTERS/$provider.sh" install --force --tools off >/dev/null
    assert_eq false "$(jq 'has("PreToolUse") or ((.hooks // {}) | has("PreToolUse"))' "$BONSAI_ADAPTER_CONFIG")" 'tools off'
    "$ADAPTERS/$provider.sh" remove >/dev/null
    assert_contains "$(cat "$BONSAI_ADAPTER_CONFIG")" 'echo mine'
    assert_contains "$("$ADAPTERS/$provider.sh" status)" not_installed
    [ "$(ls "$BONSAI_ADAPTER_CONFIG".bak-* | wc -l)" -gt 0 ]
done

export BONSAI_ADAPTER_CONFIG="$TMP/drift.json"
"$ADAPTERS/claude.sh" install --force >/dev/null
jq 'walk(if type == "string" then sub("/scripts/hooks/"; "/moved/scripts/hooks/") else . end)' "$BONSAI_ADAPTER_CONFIG" > "$TMP/drifted"
cp "$TMP/drifted" "$BONSAI_ADAPTER_CONFIG"
assert_contains "$("$ADAPTERS/claude.sh" status)" partial
"$ADAPTERS/claude.sh" install --force >/dev/null
assert_contains "$("$ADAPTERS/claude.sh" status)" installed
printf 'not json' > "$BONSAI_ADAPTER_CONFIG"
if "$ADAPTERS/claude.sh" install --force >/dev/null 2>&1; then exit 1; fi
assert_eq 'not json' "$(cat "$BONSAI_ADAPTER_CONFIG")" 'malformed input preserved'

# Copilot uses flat handlers; Gemini timeout is milliseconds; Droid is unwrapped.
assert_jq "$(cat "$TMP/copilot.json")" '.hooks.Stop[0].hooks[0].command == "echo mine"'
export BONSAI_ADAPTER_CONFIG="$TMP/gemini.json"
"$ADAPTERS/gemini.sh" install --force >/dev/null
assert_jq "$(cat "$BONSAI_ADAPTER_CONFIG")" '.hooks.BeforeAgent[0].hooks[0].timeout == 5000'
unset BONSAI_ADAPTER_CONFIG
mkdir -p "$HOME/.factory"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo legacy"}]}]}}' > "$HOME/.factory/settings.json"
"$ADAPTERS/droid.sh" install --force >/dev/null
assert_jq "$(cat "$HOME/.factory/hooks.json")" 'has("hooks") | not'
assert_contains "$(cat "$HOME/.factory/hooks.json")" 'echo legacy'

# Codex must not clobber user notify commands or synthesize hook trust.
export BONSAI_ADAPTER_CONFIG="$TMP/config.toml"
printf '%s\n' '# user comment' 'model = "mine"' '[features]' 'multi_agent = true' > "$BONSAI_ADAPTER_CONFIG"
"$ADAPTERS/codex.sh" install --force >/dev/null
first=$(cat "$BONSAI_ADAPTER_CONFIG")
"$ADAPTERS/codex.sh" install --force >/dev/null
assert_eq "$first" "$(cat "$BONSAI_ADAPTER_CONFIG")" 'Codex idempotent'
assert_contains "$("$ADAPTERS/codex.sh" status)" installed
"$ADAPTERS/codex.sh" remove >/dev/null
assert_contains "$(cat "$BONSAI_ADAPTER_CONFIG")" 'multi_agent = true'
printf '%s\n' 'notify = ["my-command"]' > "$BONSAI_ADAPTER_CONFIG"
if "$ADAPTERS/codex.sh" install --force >/dev/null 2>&1; then exit 1; fi
assert_eq 'notify = ["my-command"]' "$(cat "$BONSAI_ADAPTER_CONFIG")" 'user notify preserved'
printf '%s\n' '# tmux-bonsai notify begin' 'notify = ["mine"]' 'model = "keep"' > "$BONSAI_ADAPTER_CONFIG"
first=$(cat "$BONSAI_ADAPTER_CONFIG")
if "$ADAPTERS/codex.sh" remove >/dev/null 2>&1; then exit 1; fi
assert_eq "$first" "$(cat "$BONSAI_ADAPTER_CONFIG")" 'unbalanced markers preserved'

export BONSAI_ADAPTER_CONFIG="$TMP/statusline.json"
printf '%s\n' '{"statusLine":{"type":"command","command":"echo mine"}}' > "$BONSAI_ADAPTER_CONFIG"
if "$ADAPTERS/claude-statusline.sh" install --force >/dev/null 2>&1; then exit 1; fi
assert_contains "$(cat "$BONSAI_ADAPTER_CONFIG")" 'echo mine'
printf '{}\n' > "$BONSAI_ADAPTER_CONFIG"
"$ADAPTERS/claude-statusline.sh" install --force >/dev/null
assert_contains "$("$ADAPTERS/claude-statusline.sh" status)" installed
"$ADAPTERS/claude-statusline.sh" remove >/dev/null
assert_eq false "$(jq 'has("statusLine")' "$BONSAI_ADAPTER_CONFIG")"

export BONSAI_ADAPTER_CONFIG="$TMP/tmux-bonsai.js"
"$ADAPTERS/opencode.sh" install --force >/dev/null
assert_contains "$("$ADAPTERS/opencode.sh" status)" installed
first=$(cat "$BONSAI_ADAPTER_CONFIG")
"$ADAPTERS/opencode.sh" install --force >/dev/null
assert_eq "$first" "$(cat "$BONSAI_ADAPTER_CONFIG")" 'OpenCode idempotent'
if command -v node >/dev/null 2>&1; then
    export BONSAI_PLUGIN_TEST_DIR="$TMP/plugin-test"
    mkdir -p "$BONSAI_PLUGIN_TEST_DIR"
    cat > "$BONSAI_PLUGIN_TEST_DIR/hook" <<'SH'
#!/usr/bin/env bash
cat >> "$BONSAI_PLUGIN_TEST_DIR/events.jsonl"
printf '\n' >> "$BONSAI_PLUGIN_TEST_DIR/events.jsonl"
SH
    chmod +x "$BONSAI_PLUGIN_TEST_DIR/hook"
    node --input-type=module <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const dir = process.env.BONSAI_PLUGIN_TEST_DIR;
const source = fs.readFileSync(process.env.BONSAI_ADAPTER_CONFIG, 'utf8')
  .replace(/^const hook = .*;$/m, `const hook = ${JSON.stringify(path.join(dir, 'hook'))};`);
const moduleFile = path.join(dir, 'plugin.mjs');
fs.writeFileSync(moduleFile, source);
process.env.TMUX_PANE = '%99';
const { TmuxBonsaiPlugin } = await import(pathToFileURL(moduleFile));
const plugin = await TmuxBonsaiPlugin(undefined);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const dispatch = async (type, properties) => {
  plugin.event({event: {type, properties}});
  await pause(60);
};
await dispatch('session.created', {info: {id: 'root'}});
await dispatch('session.created', {info: {id: 'child', parentID: 'root'}});
await dispatch('message.updated', {info: {id: 'msg', role: 'assistant'}});
await dispatch('message.part.updated', {part: {sessionID: 'root', messageID: 'msg', type: 'text', text: 'first'}});
await dispatch('message.part.updated', {part: {sessionID: 'root', messageID: 'msg', type: 'text', text: 'latest coalesced text'}});
await dispatch('session.status', {sessionID: 'child', status: {type: 'busy'}});
await dispatch('session.status', {sessionID: 'child', status: {type: 'idle'}});
await dispatch('session.status', {sessionID: 'root', status: {type: 'idle'}});
const lines = fs.readFileSync(path.join(dir, 'events.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
assert.equal(lines.filter(e => e.type === 'session.created').length, 1);
assert.equal(lines.filter(e => e.type === 'message.part.updated').length, 1);
assert.ok(lines.some(e => e.type === 'SubagentStart' && e.agent_id === 'child'));
assert.ok(lines.some(e => e.type === 'SubagentStop' && e.agent_id === 'child'));
assert.ok(lines.every(e => e.root_session_id === 'root'));
assert.equal(lines.at(-1).last_assistant_message, 'latest coalesced text');
assert.equal(lines.filter(e => e.type === 'session.status').length, 1);
assert.ok(lines.every((e, i) => i === 0 || e.bonsai_seq > lines[i-1].bonsai_seq));
JS
fi
"$ADAPTERS/opencode.sh" remove >/dev/null
[ ! -f "$BONSAI_ADAPTER_CONFIG" ]

# A reducer deliberately keeps running after the hook returns. Capturing the
# hook's stdout catches inherited pipe descriptors that would stall the agent.
mkdir -p "$TMP/fixture/scripts/hooks"
cp "$TEST_ROOT"/scripts/hooks/*.sh "$TMP/fixture/scripts/hooks/"
cat > "$TMP/fixture/scripts/agent-event.sh" <<'SH'
#!/usr/bin/env bash
payload=$(cat)
sleep 2
printf '%s\n%s\n%s\n' "$1" "$2" "$payload" > "$BONSAI_FAKE_OUTPUT"
SH
chmod +x "$TMP/fixture/scripts/agent-event.sh"
export BONSAI_FAKE_OUTPUT="$TMP/dispatched"
export TMUX_PANE='%99'
started=$SECONDS
output=$(printf '{"prompt":"literal $(echo untouched)"}' | "$TMP/fixture/scripts/hooks/hook-claude.sh" UserPromptSubmit)
elapsed=$((SECONDS-started))
[ "$elapsed" -lt 2 ] || { printf 'hook retained agent pipe descriptors\n' >&2; exit 1; }
assert_eq '' "$output" 'Claude hook stdout'
assert_eq '{"continue":true}' "$(printf '{}' | "$TMP/fixture/scripts/hooks/hook-cursor.sh" beforeSubmitPrompt)"
assert_eq '{}' "$(printf '{}' | "$TMP/fixture/scripts/hooks/hook-cursor.sh" beforeShellExecution)"
unset TMUX_PANE
assert_eq '' "$(printf '{}' | "$TEST_ROOT/scripts/hooks/hook-claude.sh")" 'outside tmux no-op'
export TMUX_PANE='%99' CLAUDE_JOB_DIR=background
assert_eq '' "$(printf '{}' | "$TEST_ROOT/scripts/hooks/hook-claude.sh")" 'Claude background session no-op'
unset CLAUDE_JOB_DIR
printf 'adapter tests passed\n'
