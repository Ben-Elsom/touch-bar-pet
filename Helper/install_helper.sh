#!/bin/bash
# Installs the always-visible helper. Run it as yourself; it asks for your password.
# Needs Karabiner's driver package (8.7.0) installed and its driver extension allowed.
#
# The helper runs as root, so it's copied to a root-owned place where your user account
# can't change it. Starts at every boot. To remove: Helper/uninstall_helper.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
if [ ! -x "$DAEMON" ]; then
  echo "Karabiner's driver isn't installed." >&2
  exit 1
fi

Helper/build_helper.sh

TOOL=/Library/PrivilegedHelperTools/com.benelsom.touchbarpet.nudge
NUDGE_PLIST=/Library/LaunchDaemons/com.benelsom.touchbarpet.nudge.plist
KARABINER_PLIST=/Library/LaunchDaemons/com.benelsom.touchbarpet.karabiner-daemon.plist

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/nudge.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.benelsom.touchbarpet.nudge</string>
    <key>ProgramArguments</key><array><string>$TOOL</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
</dict>
</plist>
EOF
cat > "$TMP/karabiner.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.benelsom.touchbarpet.karabiner-daemon</string>
    <key>ProgramArguments</key><array><string>$DAEMON</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Interactive</string>
    <key>ThrottleInterval</key><integer>10</integer>
</dict>
</plist>
EOF

echo "Installing. Enter your Mac password if asked."
sudo /bin/bash -euc '
  launchctl bootout system "$3" 2>/dev/null || true
  launchctl bootout system "$4" 2>/dev/null || true
  killall Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
  mkdir -p /Library/PrivilegedHelperTools
  install -o root -g wheel -m 755 build/touchbar_nudge "$2"
  install -o root -g wheel -m 644 "$1/nudge.plist" "$3"
  install -o root -g wheel -m 644 "$1/karabiner.plist" "$4"
  launchctl bootstrap system "$4"
  launchctl bootstrap system "$3"
' _ "$TMP" "$TOOL" "$NUDGE_PLIST" "$KARABINER_PLIST"
echo "Installed. The Touch Bar now stays on while Amphetamine holds the display."
