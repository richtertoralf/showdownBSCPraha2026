#!/usr/bin/env python3
import json
import os
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

JSON_FILE = "/root/overlay/schedule.json"
OUT_DIR = "/var/overlays"
TABLES = [1, 2, 3, 4, 5, 6]
SLOT_MINUTES = 39
PREVIEW_MINUTES = 5

def load_schedule():
    with open(JSON_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    data.sort(key=lambda x: (x["date"], x["time"], x["table"]))
    return data

def referee_line(m):
    ref1 = m.get("ref1")
    ref2 = m.get("ref2")

    if ref1 and ref2:
        return f"Referee {ref1} / {ref2}\n"
    elif ref1:
        return f"Referee {ref1}\n"
    elif ref2:
        return f"Referee {ref2}\n"
    else:
        return ""

def match_text_now(m):
    group = m.get("group", "")
    line1 = f"TABLE {m['table']}"
    if group:
        line1 += f" - {group}"

    return (
        f"{line1}\n"
        f"{m['p1_nat']} {m['p1']} vs {m['p2_nat']} {m['p2']}\n"
        f"{referee_line(m)}"
    )

def match_text_next(m):
    group = m.get("group", "")
    line1 = f"NEXT TABLE {m['table']} {m['time']}"
    if group:
        line1 += f" - {group}"

    return (
        f"{line1}\n"
        f"{m['p1_nat']} {m['p1']} vs {m['p2_nat']} {m['p2']}\n"
        f"{referee_line(m)}"
    )

def atomic_write(path, content):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, path)

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    schedule = load_schedule()

    while True:
        now = datetime.now(ZoneInfo("Europe/Prague")).replace(tzinfo=None)
        today = now.strftime("%Y-%m-%d")

        for table in TABLES:
            matches = [m for m in schedule if m["date"] == today and int(m["table"]) == table]
            content = ""

            if matches:
                first_start = datetime.strptime(f"{matches[0]['date']} {matches[0]['time']}", "%Y-%m-%d %H:%M")
                if now < first_start:
                    content = f"TABLE {table}\nFirst match at {matches[0]['time']}\n"

            current = None
            next_match = None

            for i, m in enumerate(matches):
                start = datetime.strptime(f"{m['date']} {m['time']}", "%Y-%m-%d %H:%M")
                end = start + timedelta(minutes=SLOT_MINUTES)

                if start <= now < end:
                    current = m
                    if i + 1 < len(matches):
                        next_match = matches[i + 1]
                    break

                if now < start:
                    next_match = m
                    break

            if current:
                content = match_text_now(current)
            elif next_match:
                start = datetime.strptime(f"{next_match['date']} {next_match['time']}", "%Y-%m-%d %H:%M")
                if 0 <= (start - now).total_seconds() <= PREVIEW_MINUTES * 60:
                    content = match_text_next(next_match)

            atomic_write(f"{OUT_DIR}/table{table}.txt", content)

        time.sleep(15)

if __name__ == "__main__":
    main()
