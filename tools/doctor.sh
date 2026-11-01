#!/usr/bin/env bash
# Check everything the setup needs. Prints OK or what to fix. Changes nothing.
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
D="$DEVELOPER_DIR/usr/bin/devicectl"
ok() { echo "OK   $1"; }
no() { echo "FIX  $1"; echo "     -> $2"; }

[ "$(uname -m)" = arm64 ] && ok "Apple silicon Mac" || no "Apple silicon Mac" "MLX and the phone build need an M-series Mac"
[ -d /Applications/Xcode.app ] && ok "Xcode $(xcodebuild -version 2>/dev/null | head -1)" \
  || no "Xcode" "Install Xcode from the App Store, open it once"
xcodebuild -showsdks 2>/dev/null | grep -q iphoneos && ok "iOS platform" \
  || no "iOS platform" "xcodebuild -downloadPlatform iOS"
xcodebuild -showComponent metalToolchain 2>/dev/null | grep -q "Status: installed" && ok "Metal toolchain" \
  || no "Metal toolchain" "xcodebuild -downloadComponent MetalToolchain"
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null | grep -q "@" \
  && ok "Apple account signed in to Xcode" \
  || echo "?    Apple account in Xcode: can't tell from here (Xcode 26 hides it). Check Xcode > Settings > Apple Accounts."
command -v xcodegen >/dev/null && ok "xcodegen" || no "xcodegen" "brew install xcodegen"
command -v hf >/dev/null && ok "hf (Hugging Face CLI)" || no "hf" "brew install pipx && pipx install huggingface_hub"
command -v ollama >/dev/null && ok "ollama" || no "ollama" "brew install --cask ollama, then open Ollama once"
[ -x build/lmenv/bin/python ] && ok "python env for tools/ask.py" \
  || no "python env for tools/ask.py (optional)" "brew install uv && uv venv -p 3.12 build/lmenv && uv pip install -p build/lmenv/bin/python mlx-lm"

if [ ! -f data/brain.json ]; then
  no "data/brain.json" "cp -R data.example data, then fill in data/brain.json"
  exit 0
fi
ok "data/ exists"
. tools/config.sh
if [ ! -f data/icon.png ]; then
  no "data/icon.png" 'python3 tools/gen-icon.py "<prompt about the notes>"'
elif cmp -s data/icon.png data.example/icon.png; then
  no "data/icon.png is still the example tram" 'python3 tools/gen-icon.py "<prompt about the notes>"'
else
  ok "data/icon.png"
fi
grep -q "^IMAGE_API_KEY=." .env 2>/dev/null || [ -n "${IMAGE_API_KEY:-}" ] && ok "IMAGE_API_KEY for icons" \
  || no "IMAGE_API_KEY" "put an OpenAI key (or another images API) in .env, see tools/gen-icon.py"
KB=$(( $(cat data/notes/*.md 2>/dev/null | wc -c) / 1024 ))
[ "$KB" -le 60 ] && ok "notes ${KB} KB (limit 60 KB)" \
  || no "notes are ${KB} KB, limit 60 KB" "compact them (AGENTS.md, Size budget). The Mac model drops text past its 32k context."
MODEL="${BRAIN_MAC_MODEL:-qwen3.8:27b}"
ollama list 2>/dev/null | grep -q "^$MODEL " && ok "Ollama has $MODEL" || no "Ollama model $MODEL" "ollama pull $MODEL"
case "$BRAIN_TEAM_ID" in ""|ABCDE12345) no "team_id in data/brain.json" "developer.apple.com/account -> Membership details -> Team ID";; *) ok "team_id $BRAIN_TEAM_ID";; esac
case "$BRAIN_BUNDLE_ID" in *yourname*|"") no "bundle_id in data/brain.json" "pick your own, like com.alex.qwenventory";; *) ok "bundle_id $BRAIN_BUNDLE_ID";; esac
case "$BRAIN_APP_GROUP" in *yourname*|"") no "app_group in data/brain.json" "group.<your prefix>.models";; *) ok "app_group $BRAIN_APP_GROUP";; esac
if "$D" list devices 2>/dev/null | grep -q "$BRAIN_PHONE_UDID.*available"; then
  ok "iPhone connected ($BRAIN_PHONE_UDID)"
else
  no "iPhone $BRAIN_PHONE_UDID not available" "plug it in, unlock, tap Trust. Find the id with: $D list devices"
fi
