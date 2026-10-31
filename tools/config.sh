# Source this: `. tools/config.sh`. Reads data/brain.json into BRAIN_* vars.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -f "$ROOT/data/brain.json" ]; then
  echo "No data/brain.json. Run: cp -R data.example data, then fill it in." >&2
  exit 1
fi
eval "$(python3 -I - "$ROOT/data/brain.json" <<'PY'
import json, shlex, sys
c = json.load(open(sys.argv[1]))
keys = {"name": "NAME", "bundle_id": "BUNDLE_ID", "team_id": "TEAM_ID",
        "app_group": "APP_GROUP", "phone_udid": "PHONE_UDID", "mac_model": "MAC_MODEL"}
for k, v in keys.items():
    print(f"export BRAIN_{v}={shlex.quote(str(c.get(k, '')))}")
PY
)"
export BRAIN_ROOT="$ROOT"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVICECTL="$DEVELOPER_DIR/usr/bin/devicectl"
