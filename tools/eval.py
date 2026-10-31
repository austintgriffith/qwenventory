#!/usr/bin/env python3
"""Test Ollama models the way the Mac app asks them: every note in the
prompt, the time in the question. Runs data/tests.json.

  python3 tools/eval.py qwen3.8:27b
  python3 tools/eval.py qwen3.8:27b gemma4:31b      # compare models
"""
import json
import re
import sys
import time
import urllib.request

from common import DATA, day_heading, default_now, now_text, parse_now, tests, upcoming_from


def notes_text():
    return "\n\n".join(p.read_text().strip() for p in sorted((DATA / "notes").glob("*.md")))


def system():
    manifest = DATA / "files.json"
    files = json.loads(manifest.read_text()) if manifest.exists() else []
    listing = "\n".join(f"{f['file']} — {f['title']}" for f in files)
    return (DATA / "prompt-mac.txt").read_text().replace("{notes}", notes_text()).replace("{files}", listing)


def question(now, q):
    # Mirrors Notes.question in the Mac app.
    m = re.search(r"^## " + re.escape(day_heading(now)) + r"\b.*?$(.*?)(?=^## |\Z)", notes_text(), re.M | re.S)
    upcoming = upcoming_from(m.group(1))(now) if m else "(nothing scheduled today)"
    return f"NOW: {now_text(now)}\nSTILL TO COME TODAY (from the schedule):\n{upcoming}\n\nQUESTION: {q}"


def ask(model, sysmsg, q):
    body = {"model": model, "stream": False, "think": False,
            "options": {"temperature": 0, "num_ctx": 32768},
            "messages": [{"role": "system", "content": sysmsg}, {"role": "user", "content": q}]}
    req = urllib.request.Request("http://127.0.0.1:11434/api/chat", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=900).read())["message"]["content"].strip()


def main():
    cases = tests()
    if not cases:
        sys.exit("No tests. Add some to data/tests.json.")
    now = default_now()
    for model in sys.argv[1:] or ["qwen3.8:27b"]:
        ask(model, "hi", "hi")  # load it
        fails, times = [], []
        for c in cases:
            n = parse_now(c["now"]) if "now" in c else now
            t = time.time()
            a = ask(model, system(), question(n, c["q"]))
            times.append(time.time() - t)
            miss = [m for m in c.get("must", []) if m.lower() not in a.lower()]
            if miss:
                fails.append((c["q"], miss, a))
        print(f"\n=== {model}: {len(cases) - len(fails)}/{len(cases)} passed, "
              f"median {sorted(times)[len(times) // 2]:.1f}s")
        for q, miss, a in fails:
            print(f"  FAIL {q!r} missing {miss}\n    -> {a[:300]!r}")


if __name__ == "__main__":
    main()
