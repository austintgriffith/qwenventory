#!/usr/bin/env python3
"""Generate data/icon.png with an image model. Write the prompt from the notes:
the real place, thing or topic, in a rich, detailed style.

  python3 tools/gen-icon.py "Photorealistic cinematic render, iOS app icon ..."
  python3 tools/gen-icon.py --from-notes    # prompt from data/notes/00-index.md

Settings from .env (git-ignored) or the environment:
  IMAGE_API_KEY      required
  IMAGE_API_URL      default https://api.openai.com/v1/images/generations
  IMAGE_AUTH_HEADER  default Authorization (sent as "Bearer <key>").
                     Set to X-API-Key for Bankr (https://llm.bankr.bot/v1/images/generations).
  IMAGE_MODEL        default gpt-image-2
"""
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
env = dict(os.environ)
if (ROOT / ".env").exists():
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env.setdefault(k.strip(), v.strip().strip("\"'"))
key = env.get("IMAGE_API_KEY") or sys.exit("Set IMAGE_API_KEY in .env")
url = env.get("IMAGE_API_URL", "https://api.openai.com/v1/images/generations")
header = env.get("IMAGE_AUTH_HEADER", "Authorization")
if sys.argv[1:] == ["--from-notes"]:
    index = ROOT / "data" / "notes" / "00-index.md"
    about = index.read_text()[:1500] if index.exists() else ""
    prompt = ("Photorealistic cinematic render, iOS app icon composition. Show the single most iconic, specific "
              "image of the place or subject these notes are about (a famous landmark, object or scene from it, "
              "not a generic symbol). Rich detail, beautiful light, realistic materials. Notes:\n" + about)
else:
    prompt = " ".join(sys.argv[1:]) or sys.exit(__doc__)
prompt += " Square composition, subject centered and large, readable at small sizes. No text, no border, no rounded corners."

body = {"model": env.get("IMAGE_MODEL", "gpt-image-2"), "prompt": prompt, "size": "1024x1024"}
headers = {"Content-Type": "application/json",
           header: f"Bearer {key}" if header.lower() == "authorization" else key}
r = json.loads(urllib.request.urlopen(urllib.request.Request(url, json.dumps(body).encode(), headers),
                                      timeout=300).read())
out = ROOT / "data" / "icon.png"
out.write_bytes(base64.b64decode(r["data"][0]["b64_json"]))
print(f"wrote {out}. Look at it before building.")
