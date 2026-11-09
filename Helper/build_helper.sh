#!/bin/bash
# Builds build/touchbar_nudge against the client headers of the installed Karabiner
# driver version. Needs only the Command Line Tools and git.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=v8.7.0
COMMIT=5542c822dbe31dcef1435835d86f591b6fcd3aa3
SRC=build/karabiner_src

mkdir -p build
if [ ! -d "$SRC" ]; then
  git clone -q --depth 1 --branch "$TAG" \
    https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice.git "$SRC"
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$COMMIT" ]; then
  echo "Karabiner source isn't the expected commit; stopping." >&2
  exit 1
fi

clang++ -std=c++2b -O2 -w \
  -isystem "$SRC/vendor/vendor/include" -isystem "$SRC/include" \
  Helper/touchbar_nudge.cpp \
  -framework CoreFoundation -framework IOKit -framework Foundation -framework SystemConfiguration \
  -o build/touchbar_nudge
codesign --force --sign - build/touchbar_nudge >/dev/null 2>&1
echo "Built build/touchbar_nudge"
