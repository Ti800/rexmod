#!/bin/sh
# Keeps Rex patched and up to date. Sparkle can't update the patched app (its
# installer only accepts an app signed by Superlogical), so a LaunchAgent runs
# update.sh every hour and whenever Rex's Info.plist changes: it installs a
# new official Rex (checked first), patches it, and posts a notification to
# reopen Rex.
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
# Run by launchd every hour and whenever Rex's Info.plist changes. Sparkle
# can't update the patched app, so this installs new Rex versions (update.sh:
# official build, checked, then patched) and re-applies the patch when needed.
sleep 5
export REX_APP="$APP"
[ -d "\$REX_APP" ] || exit 0
out=\$("$PREFIX/scripts/update.sh" 2>&1) || out="\$out
\$("$PREFIX/scripts/patch.sh" 2>&1)"
case "\$out" in
  *"patched Rex"*|*rror*|*rejected*|*unexpected*)
    printf '%s\n%s\n' "\$(date '+%F %T')" "\$out" >> "$PREFIX/repatch.log" ;;
esac
case "\$out" in
  *"installed official Rex"*"patched Rex"*)
    msg="Rex was updated and the Changes panel re-applied. Quit Rex (⌘Q) and open it again." ;;
  *"patched Rex"*)
    msg="The Changes panel was re-applied. Quit Rex (⌘Q) and open it again." ;;
  *) exit 0 ;;
esac
/usr/bin/osascript -e "display notification \"\$msg\" with title \"rexmod\"" >/dev/null 2>&1 || true
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
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Rex re-patch agent installed ($PLIST)"
