# Direkte YouTube-Weiterleitung über MediaMTX

Dieser Ordner dokumentiert eine alternative, besonders einfache Streaming-Variante für die sechs Showdown-Tische.

Bei dieser Variante lief die YouTube-Weiterleitung direkt auf dem zentralen MediaMTX-Server. Es wurden keine separaten FFmpeg-Server und keine Overlays verwendet.

## Funktionsweise

Die Encoder veröffentlichten ihre Streams auf den MediaMTX-Pfaden:

```text
table1
table2
table3
table4
table5
table6
```

Sobald ein Pfad in MediaMTX bereit war, startete MediaMTX automatisch das Skript `yt-push.sh`.

Das Skript:

1. übernimmt den MediaMTX-Pfad aus `MTX_PATH`,
2. sucht den zugehörigen YouTube-Key in `youtube_keys.map`,
3. liest den Stream lokal per RTSP aus MediaMTX,
4. leitet Video und Audio ohne Neucodierung an YouTube weiter.

Beispiel:

```text
Encoder → MediaMTX table3 → FFmpeg → YouTube-Stream table3
```

## Monitoring

Die Streams `table1` bis `table6` waren gleichzeitig im MediaMTX-Monitoring sichtbar.

Damit konnte kontrolliert werden, ob die einzelnen Tischstreams auf dem zentralen MediaMTX-Server ankamen.

Das Monitoring bestätigte den Eingang des Streams auf MediaMTX. Es bestätigte jedoch nicht automatisch, dass YouTube den weitergeleiteten Stream erfolgreich empfing.

## Dateien

### `yt-push.sh`

Wird durch MediaMTX gestartet, sobald ein Tischstream verfügbar ist.

MediaMTX stellt dabei unter anderem folgende Umgebungsvariablen bereit:

```text
MTX_PATH
RTSP_PORT
```

### `youtube_keys.map`

Ordnet jedem MediaMTX-Pfad einen YouTube-Streamkey zu:

```ini
table1=YOUTUBE_STREAM_KEY_TABLE1
table2=YOUTUBE_STREAM_KEY_TABLE2
table3=YOUTUBE_STREAM_KEY_TABLE3
table4=YOUTUBE_STREAM_KEY_TABLE4
table5=YOUTUBE_STREAM_KEY_TABLE5
table6=YOUTUBE_STREAM_KEY_TABLE6
```

Die produktive Datei lag unter:

```text
/usr/local/etc/youtube_keys.map
```

Echte YouTube-Keys dürfen nicht in das Repository übernommen werden.

### `mediamtx-paths.yml`

Enthält den damals verwendeten Ausschnitt aus der MediaMTX-Konfiguration.

Die Regel gilt für die Pfade `table1` bis `table6`. Sobald ein Stream verfügbar ist, wird `yt-push.sh` gestartet.

## Installation damals

```text
/usr/local/bin/yt-push.sh
/usr/local/etc/youtube_keys.map
/usr/local/etc/mediamtx.yml
```

Beispielrechte:

```bash
sudo chown root:root /usr/local/bin/yt-push.sh
sudo chmod 755 /usr/local/bin/yt-push.sh

sudo chown root:root /usr/local/etc/youtube_keys.map
sudo chmod 600 /usr/local/etc/youtube_keys.map
```

## Voraussetzungen

* MediaMTX
* FFmpeg
* eingehender Stream mit YouTube-kompatiblen Codecs
* normalerweise H.264-Video und AAC-Audio
* vorher eingerichtete YouTube-Streamkeys

Da FFmpeg mit `-c copy` arbeitet, findet keine Transkodierung statt.

## Abgrenzung zur späteren Architektur

Diese Variante:

* läuft direkt auf dem MediaMTX-Server,
* verwendet keine Overlays,
* transkodiert nicht,
* benötigt keine zusätzlichen FFmpeg-Server,
* belastet die CPU nur gering.

Die spätere Architektur im Ordner `ffmpeg-table/` verwendet dagegen eigene FFmpeg-Instanzen pro Tisch, fügt Overlays hinzu, encodiert nach H.264 und sendet anschließend zu YouTube.

## Hinweis zur MediaMTX-Version

Die Konfiguration wird hier als Dokumentation des damals verwendeten Systems aufbewahrt.

Vor einer erneuten produktiven Nutzung sollte geprüft werden, ob die verwendete MediaMTX-Version weiterhin dieselben Hook-Namen und Umgebungsvariablen unterstützt.
