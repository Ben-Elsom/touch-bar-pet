#!/bin/bash
# Builds, then installs the app to ~/Applications and petsay to ~/.local/bin.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

DEST_APP="$HOME/Applications/Touch_Bar_Pet.app"
DEST_BIN="$HOME/.local/bin"

# Stop the running copy so the new one takes over.
if pgrep -x Touch_Bar_Pet >/dev/null; then
  pkill -x Touch_Bar_Pet || true
  sleep 0.5
fi

mkdir -p "$HOME/Applications" "$DEST_BIN"
rm -rf "$DEST_APP"
cp -R build/Touch_Bar_Pet.app "$DEST_APP"
# Remove first: copying over the old file in place makes macOS kill the new one
# on launch (it remembers the old signature), which silently stops every hook.
rm -f "$DEST_BIN/petsay"
cp build/petsay "$DEST_BIN/petsay"
"$DEST_BIN/petsay" --help >/dev/null

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP"
open -g "$DEST_APP"
echo "Installed $DEST_APP and $DEST_BIN/petsay"
