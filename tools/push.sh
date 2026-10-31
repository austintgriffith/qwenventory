#!/usr/bin/env bash
# Send the latest notes to the phone. No rebuild, no reinstall. The app uses
# them on the next question. Phone: plugged in (or same Wi-Fi) and unlocked.
set -euo pipefail
. "$(dirname "$0")/config.sh"
cd "$BRAIN_ROOT"

if ! "$DEVICECTL" list devices 2>/dev/null | grep -q "$BRAIN_PHONE_UDID.*available"; then
  echo "Phone not connected. Plug it in (or same Wi-Fi), unlock it, run again."; exit 1
fi

# Don't step on a model load in progress.
LOG=$(mktemp)
"$DEVICECTL" device copy from --device "$BRAIN_PHONE_UDID" --domain-type appDataContainer \
  --domain-identifier "$BRAIN_BUNDLE_ID" --source Documents/brain.log \
  --destination "$LOG" >/dev/null 2>&1 || true
if [ "$(grep -E 'load\(\) starting|model loaded' "$LOG" | tail -1 | grep -c starting)" = 1 ]; then
  echo "Phone is loading a model. Wait, then run again."; exit 1
fi

python3 -I tools/build_kb.py
cp() { "$DEVICECTL" device copy to --device "$BRAIN_PHONE_UDID" --domain-type appDataContainer \
  --domain-identifier "$BRAIN_BUNDLE_ID" --source "$1" --destination "$2" >/dev/null; }
cp ios/Resources/Brain.db Documents/Brain.db
cp ios/Resources/prompt.txt Documents/prompt.txt
for f in ios/Resources/files/*; do [ -e "$f" ] && cp "$f" "Documents/files/$(basename "$f")"; done
echo "Done. Phone has the new notes on its next question."
