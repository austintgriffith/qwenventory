#!/usr/bin/env bash
# Make the app icons from data/. Run by install-mac.sh and install-phone.sh.
#   data/icon.png (1024x1024) if it exists, else made by tools/gen-icon.py --from-notes, else
#   "icon" in data/brain.json: {"symbol": "tram.fill", "colors": ["#top", "#bottom", "#symbol"]}, else
#   the default brain.
# Output is git-ignored: ios/Resources/Icon.xcassets, mac/Icon/Icon.xcassets.
set -euo pipefail
. "$(dirname "$0")/config.sh"
cd "$BRAIN_ROOT"
SRC=build/icon-1024.png
mkdir -p build
# No icon yet: make one with the image model from the notes.
if [ ! -f data/icon.png ]; then
  python3 -I tools/gen-icon.py --from-notes \
    || echo "WARNING: no image model, using the plain fallback icon. Set IMAGE_API_KEY in .env." >&2
fi
if [ -f data/icon.png ]; then
  sips -s format png -z 1024 1024 data/icon.png --out "$SRC" >/dev/null
else
  read -r SYM TOP BOT INK < <(python3 -I -c '
import json; i = json.load(open("data/brain.json")).get("icon", {})
c = i.get("colors", []) + ["", "", ""]
print(i.get("symbol", "brain.head.profile"), c[0] or "#3373F2", c[1] or "#1A338C", c[2] or "#FFFFFF")')
  swift tools/make-icon.swift "$SRC" 1024 "$SYM" "$TOP" "$BOT" "$INK"
fi

IOS=ios/Resources/Icon.xcassets/AppIcon.appiconset
rm -rf ios/Resources/Icon.xcassets && mkdir -p "$IOS"
echo '{"info":{"author":"xcode","version":1}}' > ios/Resources/Icon.xcassets/Contents.json
cp "$SRC" "$IOS/AppIcon.png"
cat > "$IOS/Contents.json" <<'J'
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
J

MAC=mac/Icon/Icon.xcassets/AppIcon.appiconset
rm -rf mac/Icon && mkdir -p "$MAC"
echo '{"info":{"author":"xcode","version":1}}' > mac/Icon/Icon.xcassets/Contents.json
images=""
for s in 16 32 128 256 512; do
  for x in 1 2; do
    f="icon_${s}x${s}@${x}x.png"
    sips -z $((s * x)) $((s * x)) "$SRC" --out "$MAC/$f" >/dev/null
    images+="{\"filename\":\"$f\",\"idiom\":\"mac\",\"scale\":\"${x}x\",\"size\":\"${s}x${s}\"},"
  done
done
echo "{\"images\":[${images%,}],\"info\":{\"author\":\"xcode\",\"version\":1}}" > "$MAC/Contents.json"
echo "icon -> $IOS, $MAC"
