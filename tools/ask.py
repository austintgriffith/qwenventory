#!/usr/bin/env python3
"""Ask the phone's brain on this Mac: same model, same search, same prompt.
Mirrors KB.swift (search) and MLXEngine.swift (prompt + greedy decoding).
Use it to test notes before pushing them to the phone.

  build/lmenv/bin/python tools/ask.py "what's my hotel booking number"
  build/lmenv/bin/python tools/ask.py --tests            # runs data/tests.json
  build/lmenv/bin/python tools/ask.py --show "..."       # print the prompt too
"""
import argparse
import re
import sqlite3
import time
from datetime import timedelta

from common import DATA, ROOT, day_heading, default_now, now_text, parse_now, tests, upcoming_from

DB = ROOT / "ios" / "Resources" / "Brain.db"
PROMPT = DATA / "prompt-phone.txt"
MODEL_ID = "mlx-community/Qwen3.5-4B-MLX-8bit"

# Keep in sync with KB.stopwords.
STOP = set("""a an and are am as at be been but by can could did do does doing for from had has have
having he her here hers him his how i if in into is it its me my mine no nor not of off on or our ours
out over she should so some such than that the their them then there these they this those to too
under until up very was we were what when where which while who whom why will with would you your
yours tell show give get got need know want please about any much many where's what's whats when's
who's i'm im ive i've""".split())

CHUNK_LIMIT = 6
CHAR_BUDGET = 9000


def fts(q):
    w = [w for w in re.split(r"[^a-z0-9]+", q.lower()) if w and w not in STOP]
    return " OR ".join(f'"{x}"' for x in w[:12]) if w else None


def day_section(db, day):
    return db.execute("SELECT id, heading, body FROM chunks WHERE heading = ?1 OR heading LIKE ?1 || ' %' "
                      "ORDER BY id LIMIT 1", (day_heading(day),)).fetchone()


def build_system(q, now):
    db = sqlite3.connect(DB)
    picked = list(db.execute("SELECT id, heading, body FROM chunks WHERE doc = '00-index' ORDER BY id LIMIT 20"))
    for day in (now, now + timedelta(days=1)):
        r = day_section(db, day)
        if r and all(r[0] != p[0] for p in picked):
            picked.append(r)
    expr = fts(q)
    if expr:
        for r in db.execute(
            "SELECT c.id, c.heading, c.body FROM chunks_fts JOIN chunks c ON c.id = chunks_fts.rowid "
            "WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts, 3.0, 1.0) LIMIT ?", (expr, CHUNK_LIMIT + 1)):
            if all(r[0] != p[0] for p in picked):
                picked.append(r)
    out, total = [], 0
    for _, h, b in picked:
        size = len(h) + len(b) + 4
        if total + size > CHAR_BUDGET and out:
            continue
        out.append(f"## {h}\n{b}")
        total += size
    files = []
    if expr:
        files = [f"{r[0]} — {r[1]}" for r in db.execute(
            "SELECT f.file, f.title FROM files_fts JOIN files f ON f.id = files_fts.rowid "
            "WHERE files_fts MATCH ? ORDER BY bm25(files_fts) LIMIT 3", (expr,))]
    today = day_section(db, now)
    upcoming = upcoming_from(today[2])(now) if today else "(nothing scheduled today)"
    return (PROMPT.read_text().replace("{now}", now_text(now))
            .replace("{upcoming}", upcoming)
            .replace("{notes}", "\n\n".join(out) if out else "(no matching notes)")
            .replace("{files}", "\n".join(files) if files else "(none)"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("q", nargs="?")
    ap.add_argument("--tests", action="store_true", help="run data/tests.json")
    ap.add_argument("--now", help="'YYYY-MM-DD HH:MM' in the schedule's time zone")
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--model", default=MODEL_ID)
    a = ap.parse_args()
    from mlx_lm import generate, load

    model, tok = load(a.model)
    now = parse_now(a.now) if a.now else default_now()
    cases = tests() if a.tests else [{"q": a.q}]
    fails = 0
    for c in cases:
        n = parse_now(c["now"]) if "now" in c else now
        system = build_system(c["q"], n)
        if a.show:
            print(system)
        msgs = [{"role": "system", "content": system}, {"role": "user", "content": c["q"]}]
        prompt = tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False, enable_thinking=False)
        t = time.time()
        ans = re.sub(r"<think>.*?</think>", "", generate(model, tok, prompt, max_tokens=400), flags=re.S).strip()
        miss = [m for m in c.get("must", []) if m.lower() not in ans.lower()]
        fails += bool(miss)
        print(f"\nQ: {c['q']}\nA: {ans}\n({time.time() - t:.1f}s, {len(system)} chars)"
              + (f"\n  MISSING: {miss}" if miss else ""))
    if a.tests:
        print(f"\n{len(cases) - fails}/{len(cases)} passed")


if __name__ == "__main__":
    main()
