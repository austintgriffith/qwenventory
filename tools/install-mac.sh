#!/usr/bin/env bash
# Build the Mac app and put it in /Applications. Notes are read live from
# data/, so you only need this once (or after code changes).
set -euo pipefail
. "$(dirname "$0")/config.sh"
"$BRAIN_ROOT/tools/icon.sh"
cd "$BRAIN_ROOT/mac"
xcodegen generate -q
xcodebuild -project BrainMac.xcodeproj -scheme BrainMac -configuration Release \
  -derivedDataPath ../build/mac -quiet build
rm -rf "/Applications/$BRAIN_NAME.app"
cp -R "../build/mac/Build/Products/Release/$BRAIN_NAME.app" /Applications/
echo "Installed /Applications/$BRAIN_NAME.app"
