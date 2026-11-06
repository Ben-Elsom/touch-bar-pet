#!/bin/bash
# Builds build/Touch_Bar_Pet.app and build/petsay with the Command Line Tools
# (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
APP=build/Touch_Bar_Pet.app

# Some Command Line Tools releases ship two copies of the same Swift module map,
# which breaks every AppKit build. Hide the duplicate with a file overlay
# instead of deleting a system file.
FLAGS=()
CLT=/Library/Developer/CommandLineTools/usr/include/swift
if [ -f "$CLT/module.modulemap" ] && [ -f "$CLT/bridging.modulemap" ]; then
  : > build/empty.modulemap
  cat > build/vfs.yaml <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory",
  "name": "$CLT", "contents": [ { "type": "file", "name": "bridging.modulemap",
  "external-contents": "$PWD/build/empty.modulemap" } ] } ] }
EOF
  FLAGS=(-vfsoverlay build/vfs.yaml -Xcc -ivfsoverlay -Xcc build/vfs.yaml)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building Touch_Bar_Pet.app…"
swiftc -O "${FLAGS[@]}" -import-objc-header Sources/TouchBarPrivate.h \
  Sources/main.swift -o "$APP/Contents/MacOS/Touch_Bar_Pet"

echo "Building petsay…"
swiftc -O "${FLAGS[@]}" Sources/petsay.swift -o build/petsay

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Cat_Sprite_Sheet.png "$APP/Contents/Resources/"

codesign --force --sign - "$APP" >/dev/null 2>&1
codesign --force --sign - build/petsay >/dev/null 2>&1
echo "Built $APP and build/petsay"
