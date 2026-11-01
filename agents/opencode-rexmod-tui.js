// rexmod for OpenCode's terminal UI. OpenCode runs plugins in one shared
// background server, so the server half (rexmod.js) can't tell which Rex pane
// a session belongs to. This half runs in the TUI inside the pane and records
// "session -> pane" for rexmod. Installed by rexmod's scripts/install-hooks.sh;
// edits here are overwritten on the next install.
import { mkdirSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const DIR = join(homedir(), "Library", "Caches", "rexmod", "opencode")

// Polls `current` (the route has no change event; reading it is cheap) and
// writes the pane for each session the TUI shows. Returns a disposer.
function follow(current) {
  const block = process.env.REX_BLOCK
  if (!block) return () => {} // not in a Rex pane
  let last = ""
  const record = () => {
    let id = ""
    try {
      id = current() ?? ""
    } catch {}
    if (!id || id === last) return
    last = id
    try {
      mkdirSync(DIR, { recursive: true })
      writeFileSync(join(DIR, id), block + "\n")
    } catch {}
  }
  record()
  const timer = setInterval(record, 200)
  return () => clearInterval(timer)
}

// OpenCode 2: ctx.ui.router.current() is { type: "session", sessionID } on a session.
async function setup(ctx) {
  if (typeof ctx?.ui?.router?.current !== "function") return // the server, not a TUI
  const stop = follow(() => {
    const route = ctx.ui.router.current()
    return route?.type === "session" ? route.sessionID : ""
  })
  return async () => stop()
}

// OpenCode 1: api.route.current is { name: "session", params: { sessionID } }.
async function tui(api) {
  const stop = follow(() => {
    const route = api.route.current
    return route?.name === "session" ? route.params?.sessionID : ""
  })
  api.lifecycle?.onDispose?.(stop)
}

export default { id: "rexmod-tui", setup, tui }
