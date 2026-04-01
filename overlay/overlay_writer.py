#!/usr/bin/env python3

# /root/overlay/overlay_writer.py
#
# Zweck dieser Datei:
# - liest den Spielplan aus /root/overlay/schedule.json
# - erzeugt für jeden Tisch eine kleine Textdatei /var/overlays/tableX.txt
# - diese Textdatei wird von FFmpeg per drawtext(textfile=..., reload=1) live eingeblendet
#
# Warum dieses Skript existiert:
# - FFmpeg soll nur lesen und streamen, nicht die Matchlogik kennen
# - die Logik, welches Match "jetzt" oder "als nächstes" gezeigt wird,
#   liegt deshalb hier in Python
# - Änderungen an den Overlay-Texten werden über kleine Textdateien an FFmpeg übergeben
#
# Grundprinzip:
# - pro Tisch gibt es genau eine Ausgabedatei:
#     /var/overlays/table1.txt
#     /var/overlays/table2.txt
#     ...
# - FFmpeg liest diese Datei regelmäßig neu ein
# - dieses Skript aktualisiert die Inhalte alle 15 Sekunden
#
# Anzeige-Logik:
# - vor dem ersten Match eines Tages:
#     "TABLE X / First match at HH:MM"
# - während eines laufenden Matches:
#     aktuelles Match mit Spielern, Nationen und ggf. Referee(s)
# - kurz vor dem nächsten Match:
#     "NEXT TABLE X HH:MM ..."
# - wenn nichts ansteht:
#     leere Datei
#
# Wichtige Stellschrauben:
# - SLOT_MINUTES:
#     angenommene Dauer eines Match-Slots
#     darüber wird berechnet, wann ein Match als "aktuell laufend" gilt
# - PREVIEW_MINUTES:
#     wie viele Minuten vor Matchbeginn das "NEXT"-Overlay eingeblendet wird
#
# Wichtiger Praxis-Hinweis:
# - diese Datei kennt keine echten Live-Signale vom Tisch
# - sie arbeitet rein zeitbasiert auf Basis des Spielplans
# - wenn ein Match deutlich früher/später läuft als geplant,
#   kann das Overlay zeitlich vom echten Spielgeschehen abweichen
#
# Zeitbasis:
# - es wird die lokale Event-Zeitzone Europe/Prague verwendet
# - relevant für internationale Setups oder Server, die in anderer Zeitzone laufen

import json
import os
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

# Eingabedatei mit dem gesamten Spielplan im JSON-Format.
# Erwartet eine Liste von Matches mit Feldern wie:
# date, time, table, group, p1, p2, p1_nat, p2_nat, ref1, ref2
JSON_FILE = "/root/overlay/schedule.json"

# Verzeichnis für die von FFmpeg gelesenen Overlay-Textdateien.
# Pro Tisch wird dort eine Datei tableX.txt erzeugt.
OUT_DIR = "/var/overlays"

# Welche Tische aktiv bedient werden.
# Für jeden dieser Tische wird pro Schleifendurchlauf genau eine Textdatei geschrieben.
TABLES = [1, 2, 3, 4, 5, 6]

# Annahme für die Matchdauer in Minuten.
# Ein Match gilt als "current", wenn now zwischen start und start+SLOT_MINUTES liegt.
# Dieser Wert ist eine betriebliche Näherung, keine echte Live-Erkennung.
SLOT_MINUTES = 39

# Vorschau-Fenster vor dem nächsten Match.
# Nur wenn ein Spiel in <= PREVIEW_MINUTES Minuten beginnt, wird "NEXT TABLE ..."
# statt leerem Inhalt angezeigt.
PREVIEW_MINUTES = 5


def load_schedule():
    """
    Lädt den kompletten Spielplan aus der JSON-Datei und sortiert ihn.

    Sortierung:
    - zuerst nach Datum
    - dann nach Uhrzeit
    - dann nach Tisch

    Warum sortieren?
    - damit die Matches je Tisch zuverlässig in zeitlicher Reihenfolge vorliegen
    - dadurch kann später einfach das nächste Match über den Listenindex bestimmt werden
    """
    with open(JSON_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    data.sort(key=lambda x: (x["date"], x["time"], x["table"]))
    return data


def referee_line(m):
    """
    Baut die optionale Referee-Zeile für das Overlay.

    Mögliche Ausgaben:
    - "Referee A / B"
    - "Referee A"
    - "Referee B"
    - ""  (wenn kein Referee eingetragen ist)

    Das abschließende \n ist bewusst enthalten, damit die Funktion direkt
    in den mehrzeiligen Overlay-Text eingebettet werden kann.
    """
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
    """
    Baut den Overlay-Text für ein aktuell laufendes Match.

    Aufbau:
    - Zeile 1: TABLE X [- Gruppe]
    - Zeile 2: NAT Spieler1 vs NAT Spieler2
    - Zeile 3: optional Referee(s)

    Hinweis:
    - "group" wird nur angehängt, wenn das Feld im Datensatz gesetzt ist
    """
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
    """
    Baut den Overlay-Text für das nächste anstehende Match.

    Unterschied zu match_text_now():
    - Präfix "NEXT"
    - die geplante Startzeit wird in Zeile 1 eingeblendet

    Beispiel:
    NEXT TABLE 3 14:45 - bronze medal match
    """
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
    """
    Schreibt eine Datei atomar.

    Vorgehen:
    - zuerst in eine temporäre Datei schreiben
    - dann mit os.replace() in einem Schritt an den Zielnamen verschieben

    Warum wichtig?
    - FFmpeg liest die Overlay-Dateien parallel
    - ohne atomisches Schreiben könnte FFmpeg im falschen Moment eine halbfertige,
      leere oder abgeschnittene Datei erwischen
    - os.replace() tauscht die Datei auf POSIX-Systemen atomar aus
    """
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, path)


def main():
    """
    Hauptschleife des Overlay-Writers.

    Ablauf:
    1. Overlay-Verzeichnis anlegen
    2. Spielplan einmal laden
    3. Endlosschleife:
       - aktuelle Event-Zeit bestimmen
       - für jeden Tisch die relevanten Matches dieses Tages filtern
       - entscheiden, ob "current", "next", "first match" oder leer angezeigt wird
       - Textdatei für den Tisch atomar schreiben
       - 15 Sekunden warten

    Wichtiger Betriebs-Hinweis:
    - der Spielplan wird hier nur EINMAL beim Start geladen
    - wenn schedule.json während des laufenden Betriebs geändert wird,
      sieht dieses Skript die Änderungen erst nach Neustart
    - falls Live-Reload gewünscht ist, müsste load_schedule() in die Schleife
      verschoben oder ein mtime-Check eingebaut werden
    """
    os.makedirs(OUT_DIR, exist_ok=True)

    # Spielplan beim Start einlesen.
    # Aktuelle Version: statisch bis zum Neustart des Dienstes.
    schedule = load_schedule()

    while True:
        # Aktuelle Event-Zeit in Europe/Prague.
        # Danach bewusst tzinfo entfernen, damit alle weiteren Vergleiche mit den
        # per strptime erzeugten "naiven" datetime-Objekten funktionieren.
        #
        # Hintergrund:
        # - start/first_start werden unten als naive Datetimes gebaut
        # - naive und timezone-aware Datetimes lassen sich in Python nicht direkt vergleichen
        now = datetime.now(ZoneInfo("Europe/Prague")).replace(tzinfo=None)

        # Tagesfilter für den Spielplan im Format YYYY-MM-DD
        today = now.strftime("%Y-%m-%d")

        for table in TABLES:
            # Nur Matches des aktuellen Tages und des aktuellen Tisches
            matches = [m for m in schedule if m["date"] == today and int(m["table"]) == table]

            # Standard: leerer Overlay-Inhalt
            content = ""

            # Sonderfall vor dem ersten Match des Tages:
            # Dann zeigen wir statt leerem Inhalt einen Hinweis auf den ersten Start.
            if matches:
                first_start = datetime.strptime(f"{matches[0]['date']} {matches[0]['time']}", "%Y-%m-%d %H:%M")
                if now < first_start:
                    content = f"TABLE {table}\nFirst match at {matches[0]['time']}\n"

            current = None
            next_match = None

            # Bestimme laufendes oder nächstes Match.
            for i, m in enumerate(matches):
                start = datetime.strptime(f"{m['date']} {m['time']}", "%Y-%m-%d %H:%M")
                end = start + timedelta(minutes=SLOT_MINUTES)

                # Aktuelles Match:
                # now liegt innerhalb des angenommenen Slot-Fensters
                if start <= now < end:
                    current = m

                    # Falls vorhanden, auch direkt das danach folgende Match merken
                    # (wird aktuell nur logisch mitgeführt, current hat Vorrang)
                    if i + 1 < len(matches):
                        next_match = matches[i + 1]
                    break

                # Noch kein laufendes Match, aber dieses hier liegt in der Zukunft:
                # dann ist das das nächste anstehende Match
                if now < start:
                    next_match = m
                    break

            # Anzeige-Priorität:
            # 1. laufendes Match
            # 2. nächstes Match im Preview-Fenster
            # 3. First-match-Hinweis von oben
            # 4. leer
            #
            # Hinweis:
            # Der First-match-Hinweis wurde oben schon in "content" gesetzt.
            # Er bleibt nur erhalten, wenn current/next ihn nicht überschreiben.
            if current:
                content = match_text_now(current)
            elif next_match:
                start = datetime.strptime(f"{next_match['date']} {next_match['time']}", "%Y-%m-%d %H:%M")

                # "NEXT" nur kurz vor Spielbeginn anzeigen.
                # Sonst bleibt entweder der First-match-Hinweis stehen oder die Datei leer.
                if 0 <= (start - now).total_seconds() <= PREVIEW_MINUTES * 60:
                    content = match_text_next(next_match)

            # Overlay-Datei für diesen Tisch atomar aktualisieren.
            atomic_write(f"{OUT_DIR}/table{table}.txt", content)

        # Update-Intervall:
        # 15 Sekunden sind für Text-Overlays ausreichend und schonen CPU/IO.
        time.sleep(15)


if __name__ == "__main__":
    main()
