# Pure event normalization. The shell owns locking, sequence checks and writes.
def clean($n):
  (if type == "string" then . elif . == null then "" else tojson end) |
  gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "") |
  gsub("[\u0000-\u001f\u007f-\u009f]"; " ") | gsub(" +"; " ") |
  sub("^ +"; "") | sub(" +$"; "") | .[0:$n];
def preview($p):
  ($p.tool_name // $p.tool // "Tool") as $name |
  ($p.tool_input // $p.input // {}) as $input |
  ($input.command // $input.file_path // $input.path // $input.description // "") as $value |
  $name + (if $value == "" then "" else ": " + ($value | clean(120)) end);
def finish($state; $msg):
  .state = $state | .tool = "" | .msg = ($msg // .msg) |
  if .children > 0 then .parent_done = {state:.state,msg:.msg} | .state="working"
  else .parent_done=null end;
def child_start($id):
  if $id == "" then . else .child_ids = ((.child_ids + [$id]) | unique) |
    .children = (.child_ids | length) | .state="working" end;
def child_stop($id):
  .child_ids = (.child_ids | map(select(. != $id))) | .children = (.child_ids | length) |
  if .children == 0 and .parent_done != null then
    .state=.parent_done.state | .msg=.parent_done.msg | .parent_done=null
  else . end;

. as $payload | $previous |
$payload as $raw |
($raw.properties // $raw) as $p |
($p.info // {}) as $info |
($p.part // {}) as $part |
. as $old |
._ignore=false | ._boundary=false | ._reminder=false |
if $agent != "title" and $agent != "manual" and $agent != "process" then
  .type=$agent |
  .session=($raw.root_session_id // $raw.session_id // $p.session_id // $p["session-id"] // $p.rootSessionID // .session) |
  .transcript=($p.transcript_path // .transcript)
else . end |

if $agent == "title" then
  if $event == "title-settled" then
    if .state == "working" and .title_state == "idle" and
       ($now - .hook_ts >= $settle) and ($now - .title_ts >= $settle) and
       (.seq == ($p.expected_seq // .seq)) then .state="stopped"
    else ._ignore=true end
  else
    .title_state=$p.classification |
    if .title_state != $old.title_state then .title_ts=$now else . end |
    if .type == "" then .type=($p.agent // "") else . end |
    if .hook_ts == 0 or .type == "codex" then
      if .title_state == "working" then .state="working" | .parent_done=null
      elif .title_state == "permission" then .state="waiting" | .ask="Permission requested"
      elif .title_state == "idle" and .state == "working" then .state="done"
      elif .title_state == "idle" and .state == "unknown" then .state="idle" | ._boundary=true
      else . end
    else . end
  end
elif $agent == "manual" or $agent == "process" then
  if (["working","waiting","done","error","stopped","idle","exited","unknown"] | index($p.state)) != null then
    .state=$p.state | .prompt=($p.prompt // .prompt) | .msg=($p.message // $p.msg // .msg) |
    .ask=($p.ask // .ask) | .type=($p.agent // (if .type == "" then "manual" else .type end))
  else ._ignore=true end
elif $agent == "opencode" then
  if $event == "session.created" then
    if ($info.parentID // "") != "" then ._ignore=true
    else .state="idle" | ._boundary=true | .session=($info.id // .session) end
  elif ($p.bonsai_child // false) then
    if $event == "session.status" and (($p.status.type // "") == "busy" or ($p.status.type // "") == "retry") then
      child_start($p.sessionID // "")
    elif $event == "session.idle" or ($event == "session.status" and ($p.status.type // "") == "idle") then
      child_stop($p.sessionID // "")
    else ._ignore=true end
  elif $event == "session.status" then
    if ($p.status.type // "") == "busy" or ($p.status.type // "") == "retry" then .state="working" | .parent_done=null
    elif ($p.status.type // "") == "idle" then finish("done"; $raw.last_assistant_message // $p.last_assistant_message)
    else ._ignore=true end
  elif $event == "session.idle" then finish("done"; $raw.last_assistant_message // $p.last_assistant_message)
  elif $event == "session.error" then .state="error" | .msg=($p.error.data.message // $p.error.message // $p.error // $p.message // "Agent error")
  elif $event == "permission.asked" then .state="waiting" | .ask=($p.title // $p.permission // $p.tool // "Permission requested")
  elif $event == "question.asked" then .state="waiting" | .ask=($p.questions[0].question // $p.question // "Question")
  elif $event == "permission.replied" or $event == "question.replied" or $event == "question.rejected" then .state="working"
  elif $event == "message.part.updated" and ($part.type // "") == "text" and ($part.synthetic // false | not) then
    if ($p.role // $raw.role // "") == "user" then .prompt=$part.text
    elif ($p.role // $raw.role // "") == "assistant" then .msg=$part.text
    else ._ignore=true end
  elif $event == "tool.execute.before" and $tools then .state="working" | .tool=preview($p)
  elif $event == "tool.execute.after" and $tools then .state="working" | .tool=""
  else ._ignore=true end
elif $event == "StatusLine" then
  .model=($p.model.display_name // "") | .ctx=($p.context_window.used_percentage // "" | tostring)
elif $event == "Interrupt" then finish("stopped"; null)
elif $event == "agent-turn-complete" then
  finish("done"; $p["last-assistant-message"] // $p.last_assistant_message) |
  .prompt=($p["input-messages"][-1] // .prompt)
elif $event == "SessionStart" then
  if (["compact","fork"] | index($p.source // "")) != null then ._ignore=true
  else .state="idle" | ._boundary=true end
elif $event == "UserPromptSubmit" or $event == "BeforeAgent" or $event == "beforeSubmitPrompt" then
  .state="working" | .prompt=($p.prompt // $p.user_prompt // "") | .msg="" | .ask="" | .tool="" | .parent_done=null
elif $event == "PreToolUse" or $event == "BeforeTool" or $event == "preToolUse" or $event == "beforeShellExecution" or $event == "beforeMCPExecution" then
  if $tools then .state="working" | .tool=preview($p) |
    if ($p.tool_name // "") == "AskUserQuestion" then .state="waiting" | .ask=("Question: " + ($p.tool_input.questions[0].question // "Question")) else . end
  else ._ignore=true end
elif $event == "PermissionRequest" then .state="waiting" | .ask=preview($p)
elif $event == "PostToolUse" or $event == "PostToolUseFailure" or $event == "AfterTool" or $event == "postToolUse" or $event == "postToolUseFailure" then
  if $tools then .state="working" | .tool="" |
    if $event == "PostToolUseFailure" or $event == "postToolUseFailure" then .msg=($p.error // $p.message // .msg) else . end
  else ._ignore=true end
elif $event == "Notification" then
  if (["permission_prompt","elicitation_dialog","elicitation_url_dialog","agent_needs_input"] | index($p.notification_type)) != null then
    .state="waiting" | if .ask == "" then .ask=($p.message // "Input requested") else . end
  elif $p.notification_type == "idle_prompt" and (.state == "done" or .state == "waiting") and .seen_ts < .state_ts then ._reminder=true
  else ._ignore=true end
elif $event == "Stop" or $event == "stop" or $event == "AfterAgent" then
  finish((if $p.is_interrupt == true then "stopped" else "done" end); $p.last_assistant_message // $p.response // null)
elif $event == "StopFailure" or $event == "ErrorOccurred" then .state="error" | .msg=($p.error // $p.message // "Agent failed") | .tool=""
elif $event == "afterAgentResponse" then .msg=($p.text // $p.response // .msg)
elif $event == "SubagentStart" or $event == "subagentStart" then child_start($p.agent_id // $p.agentId // "")
elif $event == "SubagentStop" then child_stop($p.agent_id // $p.agentId // "")
elif $event == "PostCompact" then
  if ($p.trigger // $p.source // "") == "manual" then .state="done" | ._boundary=true else ._ignore=true end
elif $event == "SessionEnd" then .state="exited" | .tool="" | .children=0 | .child_ids=[] | .parent_done=null
else ._ignore=true end |

if ._boundary then .prompt="" | .msg="" | .ask="" | .tool="" | .children=0 | .child_ids=[] | .parent_done=null | .seen_ts=$now else . end |
if .state != "waiting" then .ask="" else . end |
if .state != $old.state then .state_ts=$now |
  if ._boundary | not then .seen_ts=([.seen_ts, $now - 1] | min) else . end
else . end |
if $agent != "title" and $agent != "manual" and $agent != "process" and (._ignore | not) then .hook_ts=$now else . end |
._category=(if ._boundary or ._ignore then ""
  elif ._reminder then (if .state == "waiting" then "input" else "finished" end)
  elif .state == $old.state then ""
  elif .state == "waiting" then "input"
  elif .state == "error" then "error"
  elif .state == "done" or .state == "stopped" then "finished"
  else "" end) |
.prompt |= clean(160) | .msg |= clean(240) | .ask |= clean(160) | .tool |= clean(120) |
.session |= clean(512) | .transcript |= clean(4096) | .type |= clean(40)
