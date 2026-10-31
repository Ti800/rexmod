// rexmod for OpenCode: records each turn for the Rex Changes panel ("Last
// Turn") and adds the review comments you left in the editor to your next
// message. It runs in OpenCode's server; rexmod finds the session's Rex pane
// through the TUI half (rexmod-tui/tui.js). Installed by rexmod's
// scripts/install-hooks.sh; edits here are overwritten on the next install.
import { spawnSync } from "node:child_process"

const REXMOD = "__REXMOD__"

// Runs `rexmod hook <event> --text`; returns the comments to add, or "".
// rexmod never fails a turn, and a missing binary is ignored here too.
function rexmod(event, cwd, sessionID) {
  try {
    const r = spawnSync(REXMOD, ["hook", event, "--text", "--agent", "opencode"], {
      input: JSON.stringify({ cwd, session_id: sessionID ?? "" }),
      encoding: "utf8",
      timeout: 15000,
    })
    return r.status === 0 ? r.stdout ?? "" : ""
  } catch {
    return ""
  }
}

const RexmodPlugin = async ({ directory }) => ({
  // A message from you starts a turn.
  "chat.message": async (input, output) => {
    const text = rexmod("prompt", directory, input.sessionID)
    if (!text.trim()) return
    const first = output.parts.find((p) => p.type === "text")
    output.parts.push({
      // Sorts right after your own text.
      id: (first?.id ?? `prt_${Date.now().toString(16)}`) + "rexmod",
      sessionID: input.sessionID,
      messageID: output.message.id,
      type: "text",
      text,
      synthetic: true,
    })
  },
  // The session going idle ends it.
  event: async ({ event }) => {
    if (event.type === "session.idle") rexmod("stop", directory, event.properties?.sessionID)
  },
})

export default { id: "rexmod", server: RexmodPlugin }
