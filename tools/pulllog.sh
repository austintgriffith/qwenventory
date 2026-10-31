#!/usr/bin/env bash
# Print the phone app's debug log (Documents/brain.log).
set -euo pipefail
. "$(dirname "$0")/config.sh"
LOG=$(mktemp)
"$DEVICECTL" device copy from --device "$BRAIN_PHONE_UDID" --domain-type appDataContainer \
  --domain-identifier "$BRAIN_BUNDLE_ID" --source Documents/brain.log --destination "$LOG" >/dev/null
cat "$LOG"
