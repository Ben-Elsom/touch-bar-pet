#!/bin/bash
# Removes the always-visible helper. Add --driver to remove Karabiner's driver as well.
set -euo pipefail

NUDGE_PLIST=/Library/LaunchDaemons/com.benelsom.touchbarpet.nudge.plist
KARABINER_PLIST=/Library/LaunchDaemons/com.benelsom.touchbarpet.karabiner-daemon.plist
SCRIPTS="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall"

sudo /bin/bash -c '
  launchctl bootout system "$1" 2>/dev/null || true
  launchctl bootout system "$2" 2>/dev/null || true
  killall Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
  rm -f "$1" "$2" /Library/PrivilegedHelperTools/com.benelsom.touchbarpet.nudge
' _ "$NUDGE_PLIST" "$KARABINER_PLIST"
echo "Helper removed."

if [ "${1:-}" = "--driver" ]; then
  bash "$SCRIPTS/deactivate_driver.sh"
  sudo bash "$SCRIPTS/remove_files.sh"
  echo "Driver removed."
fi
