# Security policy

rexmod changes how Rex runs on your Mac: it patches your copy of Rex to load a
library, re-signs it ad hoc, installs a LaunchAgent and adds hooks to your
coding agents. Problems in any of that are worth reporting.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through
[GitHub's security advisories](https://github.com/alpcanaydin/rexmod/security/advisories/new)
with what you found, how to reproduce it and which versions are affected. You'll
get an answer within a few days, and a fix and an advisory when it's confirmed.

## Supported versions

Fixes go into the latest release. Update with `brew upgrade rexmod && rexmod-setup`,
or run the install command again.

## What rexmod touches

- `/Applications/Rex Beta.app`: a weak load command for
  `~/Library/Application Support/rexmod/RexModPanel.dylib`, and an ad hoc
  signature that allows loading it. The official build is backed up first, and
  `uninstall.sh` restores it. `update.sh` checks a downloaded Rex's signature,
  Team ID and notarization before patching it.
- `~/Library/LaunchAgents/dev.rexmod.repatch.plist`: re-applies the patch after
  Rex updates itself.
- Agent configuration: hooks in `~/.claude/settings.json` and
  `~/.codex/hooks.json`, plugins in `~/.config/opencode`, an extension in
  `~/.pi/agent`. Each JSON file is backed up before it changes.
