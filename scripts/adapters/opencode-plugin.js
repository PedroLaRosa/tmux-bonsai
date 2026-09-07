// tmux-bonsai managed opencode plugin v1
import { spawn } from "node:child_process";

const hook = __BONSAI_HOOK_PATH__;
const toolEvents = __BONSAI_TOOL_EVENTS__;

// The directory plugin loader invokes named function exports. Do not export a
// second object/function: older loaders call every export as a plugin factory.
export const TmuxBonsaiPlugin = async (ctx) => {
  const sessions = new Map();
  const roles = new Map();
  const previews = new Map();
  const lastSent = new Map();
  let seq = Date.now() * 1000;
  const trimCache = (map) => {
    if (map.size > 256) map.delete(map.keys().next().value);
  };
  const rootOf = async (id) => {
    let current = id;
    const visited = new Set();
    while (current && !visited.has(current)) {
      visited.add(current);
      if (!sessions.has(current)) {
        try {
          const result = await ctx?.client?.session?.get({ path: { id: current } });
          const info = result?.data;
          if (!info) return null;
          sessions.set(current, info.parentID || null);
          trimCache(sessions);
        } catch { return null; }
      }
      const parent = sessions.get(current);
      if (!parent) return current;
      current = parent;
    }
    return null;
  };
  const emit = (event, root, fields = {}) => {
    if (!process.env.TMUX_PANE) return;
    try {
      seq = Math.max(seq + 1, Date.now() * 1000);
      const payload = JSON.stringify({ ...event, ...fields,
        session_id: root, root_session_id: root, bonsai_seq: seq });
      const child = spawn(hook, [event.type], {
        detached: true, stdio: ["pipe", "ignore", "ignore"],
        env: { ...process.env, BONSAI_EVENT_SEQ: String(seq) },
      });
      child.on("error", () => {});
      child.stdin.on("error", () => {});
      child.stdin.end(payload);
      child.unref();
    } catch { /* Tracking must never interrupt the agent. */ }
  };
  const handle = async (event) => {
    if (!process.env.TMUX_PANE || !event?.type) return;
    const props = event.properties || {};
    const info = props.info || {};
    if (event.type === "session.created" || event.type === "session.updated") {
      if (!info.id) return;
      sessions.set(info.id, info.parentID || null);
      trimCache(sessions);
      if (event.type === "session.created" && !info.parentID) emit(event, info.id);
      return;
    }
    if (event.type === "session.deleted") {
      sessions.delete(info.id); previews.delete(info.id); lastSent.delete(info.id);
      return;
    }
    if (event.type === "message.updated") {
      if (info.id) { roles.set(info.id, info.role); trimCache(roles); }
      return;
    }
    const part = props.part || {};
    const id = props.sessionID || info.sessionID || part.sessionID;
    if (!id) return;
    const root = await rootOf(id);
    if (!root) return;
    const child = root !== id;
    if (event.type === "message.part.updated") {
      if (child || part.type !== "text" || part.synthetic) return;
      const role = roles.get(part.messageID);
      if (role !== "user" && role !== "assistant") return;
      const preview = previews.get(root) || {};
      // Keep only the current text part; pane options are small previews, not a
      // transcript. Flush the latest assistant text together with completion.
      if (role === "user") {
        preview.prompt = String(part.text || "").slice(0, 160);
        preview.last_assistant_message = "";
      } else preview.last_assistant_message = String(part.text || "").slice(0, 240);
      previews.set(root, preview); trimCache(previews);
      if (role === "user" || Date.now() - (lastSent.get(root) || 0) >= 1000) {
        emit(event, root, { ...preview, role });
        lastSent.set(root, Date.now()); trimCache(lastSent);
      }
      return;
    }
    if (/^(permission|question)\.(asked|replied|rejected)$/.test(event.type)) {
      // Child waits require attention too; child completion never finishes the
      // parent's turn. Keep root attribution while retaining original payload.
      emit(event, root, { child_session_id: child ? id : undefined });
      return;
    }
    if (child) {
      if (event.type === "session.status" || event.type === "session.idle") {
        const status = props.status?.type;
        if (status === "busy" || status === "retry") {
          emit({ type: "SubagentStart" }, root, { agent_id: id, agent_type: "opencode" });
        } else if (status === "idle" || event.type === "session.idle") {
          emit({ type: "SubagentStop" }, root, { agent_id: id, agent_type: "opencode" });
        }
      }
      return;
    }
    if (/^session\.(status|idle|error)$/.test(event.type)) {
      emit(event, root, previews.get(root) || {});
    }
  };
  const tool = (type, input, output) => {
    if (!toolEvents) return;
    void (async () => {
      const root = await rootOf(input.sessionID);
      if (!root || root !== input.sessionID) return;
      emit({ type, properties: { sessionID: root, tool_name: input.tool,
        tool_input: output?.args || input.args || {} } }, root);
    })().catch(() => {});
  };
  return {
    event: ({ event }) => { void handle(event).catch(() => {}); },
    "tool.execute.before": (input, output) => tool("tool.execute.before", input, output),
    "tool.execute.after": (input, output) => tool("tool.execute.after", input, output),
  };
};
