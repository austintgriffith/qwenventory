"""Shared bits for ask.py and eval.py. Mirrors KB.swift and mac/App/Data.swift."""
import json
import re
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
CONFIG = json.loads((DATA / "brain.json").read_text())
TZ = ZoneInfo(CONFIG.get("timezone") or "UTC")
HOME = ZoneInfo(CONFIG["home_timezone"]) if CONFIG.get("home_timezone") else None
TIME_RE = re.compile(r"^~?(\d{1,2}):(\d{2})\s*(AM|PM)?", re.I)


def parse_now(s):
    """'2026-11-03 09:00' in the schedule's time zone."""
    return datetime.strptime(s, "%Y-%m-%d %H:%M").replace(tzinfo=TZ)


def day_heading(now):
    return now.strftime("%a %b ") + str(now.day)  # "Tue Nov 3"


def now_text(now):
    s = now.strftime("%a %b %-d, %Y, %-I:%M %p") + f" ({TZ.key})"
    if HOME:
        s += f". Home time ({HOME.key}): " + now.astimezone(HOME).strftime("%a %-I:%M %p")
    return s + ". Today is " + day_heading(now) + ". Tomorrow is " + day_heading(now + timedelta(days=1)) + "."


def upcoming_from(body):
    """Schedule lines from 15 minutes ago on, given today's section body."""
    def f(now):
        cutoff = now.hour * 60 + now.minute - 15
        out = []
        for line in body.splitlines():
            m = TIME_RE.match(line.strip())
            if not m:
                continue
            h, mi, ap = int(m.group(1)), int(m.group(2)), (m.group(3) or "").upper()
            if ap == "PM" and h < 12:
                h += 12
            if ap == "AM" and h == 12:
                h = 0
            if h * 60 + mi >= cutoff:
                out.append(line.strip())
        return "\n".join(out) if out else "(nothing else today)"
    return f


def tests():
    p = DATA / "tests.json"
    return json.loads(p.read_text()) if p.exists() else []


def default_now():
    return parse_now(CONFIG.get("test_now") or datetime.now(TZ).strftime("%Y-%m-%d %H:%M"))
