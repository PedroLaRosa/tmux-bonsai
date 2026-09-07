# Remove only our handlers; preserve neighboring user handlers and matchers.
def managed:
  (.command // .bash // "") as $c |
  ($c | endswith(" # tmux-bonsai:" + $agent)) or
  ($c | test("/scripts/hooks/hook-" + $agent + "\\.sh(?:['\" ]|$)"));
def remove_managed:
  if has("hooks") then
    .hooks |= with_entries(
      .value |= map(
        if has("hooks") then
          .hooks |= map(select(managed | not)) |
          select(.hooks | length > 0)
        else select(managed | not) end
      ) | select(.value | length > 0)
    )
  else . end;
if $action == "remove" then remove_managed
elif $action == "inspect" then
  [(.hooks // {}) | to_entries[] | .key as $event | .value[] |
    (if has("hooks") then .hooks |= map(select(managed)) | select(.hooks | length > 0)
     else select(managed) end) | {event: $event, entry: .}] | sort_by(.event, .entry.command // .entry.bash)
elif $action == "install" then
  remove_managed |
  .hooks = (.hooks // {}) |
  reduce ($events | split(" ")[] | select(length > 0)) as $event (.;
    ($command + " " + $event + " # tmux-bonsai:" + $agent) as $cmd |
    (if $shape == "cursor" then {command: $cmd, timeout: 5}
     elif $shape == "copilot" then {type: "command", bash: $cmd, timeoutSec: 5}
     else {matcher: (if ($event | test("Tool|PermissionRequest")) then "*" else "" end),
           hooks: [{type: "command", command: $cmd,
             timeout: (if $shape == "gemini" then 5000
                       elif ($event == "Interrupt" or $event == "SessionEnd") and $agent == "codex" then 3
                       else 5 end)}]} end) as $entry |
    .hooks[$event] = ((.hooks[$event] // []) + [$entry])
  ) |
  if $shape == "cursor" or $shape == "copilot" then .version = (.version // 1) else . end
else error("unknown adapter operation") end
