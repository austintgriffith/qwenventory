#!/usr/bin/env python3
"""Build ios/Resources/ from data/: Brain.db (search index), prompt.txt and
files/. Each "## heading" section of a note becomes one searchable chunk.
Settings from data/brain.json go in the db's meta table for the phone.

Run by tools/push.sh and tools/install-phone.sh. No need to run it by hand.
"""
import json
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
NOTES = DATA / "notes"
FILES = DATA / "files"
MANIFEST = DATA / "files.json"
RES = ROOT / "ios" / "Resources"
DB = RES / "Brain.db"


def chunks_of(path):
    doc = path.stem
    title = doc
    heading, lines, out = None, [], []
    for line in path.read_text().splitlines():
        if line.startswith("# ") and heading is None and not lines:
            title = line[2:].strip()
            continue
        if line.startswith("## "):
            if heading or any(l.strip() for l in lines):
                out.append((doc, title, heading or title, "\n".join(lines).strip()))
            heading, lines = line[3:].strip(), []
        else:
            lines.append(line)
    if heading or any(l.strip() for l in lines):
        out.append((doc, title, heading or title, "\n".join(lines).strip()))
    return out


def main():
    RES.mkdir(parents=True, exist_ok=True)
    if DB.exists():
        DB.unlink()
    db = sqlite3.connect(DB)
    db.executescript(
        """
        CREATE TABLE chunks(id INTEGER PRIMARY KEY, doc TEXT, doc_title TEXT, heading TEXT, body TEXT);
        CREATE VIRTUAL TABLE chunks_fts USING fts5(heading, body, content='chunks', content_rowid='id',
            tokenize='porter unicode61');
        CREATE TABLE files(id INTEGER PRIMARY KEY, file TEXT, title TEXT, keywords TEXT);
        CREATE VIRTUAL TABLE files_fts USING fts5(title, keywords, content='files', content_rowid='id',
            tokenize='porter unicode61');
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
        """
    )
    n = 0
    for path in sorted(NOTES.glob("*.md")):
        for doc, title, heading, body in chunks_of(path):
            if not body:
                continue
            cur = db.execute(
                "INSERT INTO chunks(doc, doc_title, heading, body) VALUES (?,?,?,?)",
                (doc, title, heading, body),
            )
            db.execute(
                "INSERT INTO chunks_fts(rowid, heading, body) VALUES (?,?,?)",
                (cur.lastrowid, heading, body),
            )
            n += 1

    dest = RES / "files"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir()
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else []
    for entry in manifest:
        src = FILES / entry["file"]
        if not src.exists():
            raise SystemExit(f"missing file: {src}")
        shutil.copy2(src, dest / entry["file"])
        cur = db.execute(
            "INSERT INTO files(file, title, keywords) VALUES (?,?,?)",
            (entry["file"], entry["title"], entry.get("keywords", "")),
        )
        db.execute(
            "INSERT INTO files_fts(rowid, title, keywords) VALUES (?,?,?)",
            (cur.lastrowid, entry["title"], entry.get("keywords", "")),
        )

    config = json.loads((DATA / "brain.json").read_text())
    meta = {
        "built": datetime.now().strftime("%b %-d, %-I:%M %p"),
        "name": config.get("name", "Qwenventory"),
        "subtitle": config.get("subtitle", "private · works offline"),
        "timezone": config.get("timezone", ""),
        "home_timezone": config.get("home_timezone", ""),
        "examples": json.dumps(config.get("examples", [])),
    }
    db.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
    db.commit()
    db.close()
    shutil.copy2(DATA / "prompt-phone.txt", RES / "prompt.txt")
    print(f"{n} chunks, {len(manifest)} files -> {DB}")


if __name__ == "__main__":
    main()
