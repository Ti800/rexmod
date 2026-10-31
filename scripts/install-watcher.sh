#!/bin/sh
# Re-applies the patch whenever Rex updates itself. Sparkle replaces the
# patched app with the official build (seen: 1726 -> 1728), which drops the
# panel. A LaunchAgent watches Rex's Info.plist and runs patch.sh after an
# update, then posts a notification to reopen Rex.
#
#   install-watcher.sh            install and load the agent
#   install-watcher.sh --remove   unload and delete it
set -eu
PREFIX="$HOME/Library/Application Support/rexmod"
APP="${REX_APP:-/Applications/Rex Beta.app}"
LABEL="dev.rexmod.repatch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
RUNNER="$PREFIX/scripts/repatch-after-update.sh"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$RUNNER"
  echo "removed the Rex re-patch agent"
  exit 0
fi

[ -x "$PREFIX/scripts/patch.sh" ] || { echo "run install.sh first ($PREFIX/scripts/patch.sh is missing)" >&2; exit 1; }
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$RUNNER" <<RUN
#!/bin/sh
# Run by launchd when Rex's Info.plist changes. Waits for the update to settle.
sleep 5
export REX_APP="$APP"
[ -d "\$REX_APP" ] || exit 0
"$PREFIX/scripts/patch.sh" --check >/dev/null 2>&1 && exit 0
echo "\$(date '+%F %T') Rex changed; patching" >> "$PREFIX/repatch.log"
"$PREFIX/scripts/patch.sh" >> "$PREFIX/repatch.log" 2>&1 || exit 1
/usr/bin/osascript -e 'display notification "Rex updated; the Changes panel was re-applied. Quit Rex (⌘Q) and open it again." with title "rexmod"' >/dev/null 2>&1 || true
RUN
chmod 755 "$RUNNER"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$RUNNER</string></array>
  <key>WatchPaths</key><array><string>$APP/Contents/Info.plist</string></array>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Rex re-patch agent installed ($PLIST)"
