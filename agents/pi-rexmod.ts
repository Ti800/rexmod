// rexmod for Pi: records each turn for the Rex Changes panel ("Last Turn")
// and adds the review comments you left in the editor to your next message.
// Installed by rexmod's scripts/install-hooks.sh; edits here are overwritten
// on the next install.
import { spawnSync } from "node:child_process"

const REXMOD = "__REXMOD__"

// Runs `rexmod hook <event> --text`; returns the comments to add, or "".
// rexmod never fails a turn, and a missing binary is ignored here too.
function rexmod(event: string, cwd: string, sessionId: string): string {
  try {
    const r = spawnSync(REXMOD, ["hook", event, "--text"], {
      input: JSON.stringify({ cwd, session_id: sessionId }),
      encoding: "utf8",
      timeout: 15000,
    })
    return r.status === 0 ? (r.stdout ?? "") : ""
  } catch {
    return ""
  }
}

function sessionId(ctx: any): string {
  try {
    return ctx.sessionManager.getSessionId() ?? ""
  } catch {
    return ""
  }
}

export default function (pi: any) {
  // A message from you starts a turn; pending comments ride along with it.
  pi.on("before_agent_start", async (_event: any, ctx: any) => {
    const text = rexmod("prompt", ctx.cwd, sessionId(ctx))
    if (!text.trim()) return
    return { message: { customType: "rexmod-review", content: text, display: true } }
  })
  // Pi is done (retries and queued work included): the turn ends.
  pi.on("agent_settled", async (_event: any, ctx: any) => {
    rexmod("stop", ctx.cwd, sessionId(ctx))
  })
}
