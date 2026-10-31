#!/usr/bin/env bash
# Build the iPhone app and install it. First build takes ~20 min (MLX).
# Phone: plugged in and unlocked.
set -euo pipefail
. "$(dirname "$0")/config.sh"
cd "$BRAIN_ROOT"
python3 -I tools/build_kb.py
cd ios
xcodegen generate -q
xcodebuild -project Brain.xcodeproj -scheme Brain -destination 'generic/platform=iOS' \
  -configuration Release -derivedDataPath ../build/ios -allowProvisioningUpdates -quiet build
"$DEVICECTL" device install app --device "$BRAIN_PHONE_UDID" ../build/ios/Build/Products/Release-iphoneos/Brain.app
echo "Installed. If the model isn't on the phone yet, run tools/copy-model.sh before opening the app."
