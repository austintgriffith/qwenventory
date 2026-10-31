#!/usr/bin/env bash
# Build the iPhone app and install it. First build takes ~20 min (MLX).
# Phone: plugged in and unlocked.
set -euo pipefail
. "$(dirname "$0")/config.sh"
cd "$BRAIN_ROOT"
python3 -I tools/build_kb.py
tools/icon.sh
cd ios
xcodegen generate -q

build() {
  xcodebuild -project Brain.xcodeproj -scheme Brain -destination 'generic/platform=iOS' \
    -configuration Release -derivedDataPath ../build/ios -allowProvisioningUpdates -quiet build 2>&1
}
if ! out=$(build); then
  if grep -q "No Accounts" <<<"$out"; then
    # Xcode 26 keeps the Apple account where xcodebuild can't see it. A build
    # inside Xcode makes the signing profile, then the command line works.
    echo "Making the signing profile with a build inside Xcode..."
    open Brain.xcodeproj
    sleep 5
    osascript -e 'tell application "Xcode"
      set r to build (active workspace document)
      repeat 1800 times
        if completed of r then exit repeat
        delay 1
      end repeat
      return status of r as text
    end tell'
    out=$(build) || { echo "$out" | grep -E "error" | head; exit 1; }
  else
    echo "$out" | grep -E "error" | head; exit 1
  fi
fi
"$DEVICECTL" device install app --device "$BRAIN_PHONE_UDID" ../build/ios/Build/Products/Release-iphoneos/Brain.app
echo "Installed. If the model isn't on the phone yet, run tools/copy-model.sh before opening the app."
