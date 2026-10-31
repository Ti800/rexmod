// rexmod for OpenCode's terminal UI. OpenCode 2 runs plugins in one shared
// background server, so the server half (rexmod.js) can't tell which Rex pane
// a session belongs to. This half runs in the TUI inside the pane and records
// "session -> pane" for rexmod. Installed by rexmod's
// scripts/install-hooks.sh; edits here are overwritten on the next install.
import { mkdirSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const DIR = join(homedir(), "Library", "Caches", "rexmod", "opencode")

const tui = async (api) => {
  const block = process.env.REX_BLOCK
  if (!block) return // not in a Rex pane
  let last = ""
  const record = () => {
    const route = api.route.current
    const id = route?.name === "session" ? route.params?.sessionID : ""
    if (!id || id === last) return
    last = id
    try {
      mkdirSync(DIR, { recursive: true })
      writeFileSync(join(DIR, id), block + "\n")
    } catch {}
  }
  // The route has no change event; reading it is cheap.
  const timer = setInterval(record, 200)
  for (const type of ["session.created", "session.updated", "session.status", "message.updated"]) {
    try {
      api.event.on(type, record)
    } catch {}
  }
  api.lifecycle.onDispose(() => clearInterval(timer))
  record()
}

export default { id: "rexmod-tui", tui }
