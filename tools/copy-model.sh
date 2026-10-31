#!/usr/bin/env bash
# Copy a phone model from this Mac to the iPhone over USB. The phone never
# downloads it. Install the app first (that creates the App Group folder),
# but don't open it until this finishes.
#
#   tools/copy-model.sh                                   # default 4B 8-bit
#   tools/copy-model.sh mlx-community/Qwen3.5-4B-MLX-4bit
#   tools/copy-model.sh <model> --force                 # copy even if there
set -euo pipefail
. "$(dirname "$0")/config.sh"
MODEL="${1:-mlx-community/Qwen3.5-4B-MLX-8bit}"
DIR="models--${MODEL//\//--}"
HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"

# 1. Get it onto the Mac (skips files already there).
hf download "$MODEL" >/dev/null
SNAP=$(cat "$HUB/$DIR/refs/main")

# Another Qwenventory on the same App Group may have copied it already.
have=$("$DEVICECTL" device info files --device "$BRAIN_PHONE_UDID" \
  --domain-type appGroupDataContainer --domain-identifier "$BRAIN_APP_GROUP" \
  --subdirectory "Library/huggingface/hub/$DIR/snapshots/$SNAP" 2>&1 || true)
if [ "${2:-}" != "--force" ] && grep -q safetensors <<<"$have"; then
  echo "Already on the phone (shared). Nothing to copy. Add --force to copy again."; exit 0
fi

# 2. Copy each real file (not the symlink) into the App Group folder.
# Writes only work under Library/ in a group container.
dest="Library/huggingface/hub/$DIR"
put() { "$DEVICECTL" device copy to --device "$BRAIN_PHONE_UDID" --domain-type appGroupDataContainer \
  --domain-identifier "$BRAIN_APP_GROUP" --source "$1" --destination "$2" >/dev/null; }
for f in "$HUB/$DIR/snapshots/$SNAP"/*; do
  name=$(basename "$f")
  echo "copying $name ($(du -hL "$f" | cut -f1))"
  put "$(readlink -f "$f")" "$dest/snapshots/$SNAP/$name"
done
put "$HUB/$DIR/refs/main" "$dest/refs/main"
echo "Done. Open the app."
