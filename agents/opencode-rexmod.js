// rexmod for OpenCode: records each turn for the Rex Changes panel ("Last
// Turn") and adds the review comments you left in the editor to your next
// message. It runs in OpenCode's server, which serves every pane; rexmod finds
// the session's Rex pane through the TUI half (rexmod-tui/tui.js). Installed
// by rexmod's scripts/install-hooks.sh; edits here are overwritten.
import { spawnSync } from "node:child_process"

const REXMOD = "__REXMOD__"

// Runs `rexmod hook <event> --text`; returns the comments to add, or "".
// rexmod never fails a turn, and a missing binary is ignored here too.
function rexmod(event, cwd, sessionID) {
  try {
    const r = spawnSync(REXMOD, ["hook", event, "--text", "--agent", "opencode"], {
      input: JSON.stringify({ cwd: cwd ?? "", session_id: sessionID ?? "" }),
      encoding: "utf8",
      timeout: 15000,
    })
    return r.status === 0 ? r.stdout ?? "" : ""
  } catch {
    return ""
  }
}

// OpenCode 2: hooks and events on the plugin context.
async function setup(ctx) {
  if (!ctx || typeof ctx.session?.hook !== "function") return
  // A message from you starts a turn; pending comments join its text.
  await ctx.session.hook("prompt", async (input) => {
    const text = rexmod("prompt", "", input?.sessionID)
    if (text.trim() && input?.prompt) {
      input.prompt.text = `${input.prompt.text ?? ""}\n\n${text}`
    }
  })
  if (typeof ctx.event?.subscribe !== "function") return
  // The session finishing (or failing, or being stopped) ends the turn.
  const controller = new AbortController()
  ;(async () => {
    for await (const ev of ctx.event.subscribe({ signal: controller.signal })) {
      if (/^session\.execution\.(succeeded|failed|interrupted)$/.test(ev?.type ?? "")) {
        rexmod("stop", "", ev.data?.sessionID)
      }
    }
  })().catch(() => {})
  return async () => controller.abort()
}

// OpenCode 1: the same through chat.message and session.idle.
const server = async ({ directory }) => ({
  "chat.message": async (input, output) => {
    const text = rexmod("prompt", directory, input.sessionID)
    if (!text.trim()) return
    const first = output.parts.find((p) => p.type === "text")
    output.parts.push({
      id: (first?.id ?? `prt_${Date.now().toString(16)}`) + "rexmod", // sorts right after your text
      sessionID: input.sessionID,
      messageID: output.message.id,
      type: "text",
      text,
      synthetic: true,
    })
  },
  event: async ({ event }) => {
    if (event.type === "session.idle") rexmod("stop", directory, event.properties?.sessionID)
  },
})

export default { id: "rexmod", setup, server }
