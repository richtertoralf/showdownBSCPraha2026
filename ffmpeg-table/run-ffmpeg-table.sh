#!/bin/sh

# ----------------------------------
# Pfad:
# /usr/local/bin/run-ffmpeg-table.sh
# ----------------------------------
#
# FFmpeg-Skript für einen einzelnen Tisch-Stream.
#
# Zweck dieser Datei:
# - liest einen RTSP-Stream für einen Tisch ein
# - blendet das Text-Overlay aus /var/overlays/tableX.txt ein
# - encodiert das Video nach H.264 für YouTube
# - reicht das Audio unverändert durch
# - sendet das Ergebnis per RTMP an YouTube
#
# Warum diese Datei existiert:
# - pro Tisch läuft ein eigener FFmpeg-Prozess
# - die Basisparameter kommen aus /etc/ffmpeg-table.env
# - diese Datei ist die zentrale Stelle für:
#   - RTSP-Quelle
#   - Overlay
#   - Video-Encoding
#   - AV-Feinabgleich
#   - YouTube-Ausgabe
#
# ----------------
# Overlay-Hinweis:
# ----------------
#
# - /var/overlays/table${TABLE}.txt wird durch reload=1 laufend neu gelesen
# - Änderungen am Overlay-Text werden daher ohne Neustart sichtbar
# - Das Overlay steht unten links mit 40 px Abstand zum Rand
# - y=h-text_h-40 bedeutet:
#   Der Textblock wird dynamisch an der unteren Bildkante ausgerichtet,
#   unabhängig davon, wie viele Zeilen der Text gerade hat
#
# Gestaltung des Overlays:
# - Das Overlay besteht bewusst aus ZWEI übereinanderliegenden drawtext-Layern
# - beide Layer lesen denselben Text aus derselben Datei
#
# Layer 1:
# - erzeugt eine größere, helle, halbtransparente Hintergrundfläche
# - boxcolor=lightblue@0.16
# - boxborderw=13
# - fontcolor=black@0, also Text selbst unsichtbar
# - Zweck: weicher, freundlicher Hintergrund / Markenwirkung / Abhebung
#
# Layer 2:
# - zeichnet den eigentlichen sichtbaren Text in weiß
# - mit leichter Kontur, Schatten und dunkler halbtransparenter Box
# - boxcolor=black@0.32
# - bordercolor=black@0.35
# - shadowcolor=black@0.22
# - Zweck: gute Lesbarkeit auch auf unruhigem Bildinhalt
#
# Warum zwei Layer:
# - ein einzelner drawtext-Layer war optisch zu hart oder zu schlecht lesbar
# - die Kombination aus heller Außenfläche und dunkler Textbox erzeugt
#   bessere Lesbarkeit und zugleich einen weicheren, wertigeren Look
#
# Was man bei Bedarf anpassen kann:
# - fontsize=34           -> Schriftgröße
# - line_spacing=5        -> Abstand zwischen Textzeilen
# - boxborderw=13 / 10    -> Dicke der Hintergrund-/Rahmenfläche
# - x=40 / y=...          -> Position des Overlays
# - lightblue@0.16        -> Farbe/Transparenz der äußeren Fläche
# - black@0.32            -> Dunkelheit der inneren Textbox
#
# Vorsicht bei Änderungen:
# - kleine Transparenzänderungen haben große optische Wirkung
# - zu starke Box-Farben wirken schnell klobig
# - zu wenig Kontrast macht Spielernamen und Ansetzungen schlecht lesbar
#
# -----------------
# Transport-Hinweis
# -----------------
#
# - RTSP wird hier bewusst über TCP gelesen, um die Strecke stabiler
#   gegen Paketverluste und Jitter zu machen
# - das ist für Eventbetrieb meist robuster als UDP
#
# ---------------------------
# WICHTIG ZUR AV-SYNCHRONITÄT
# ---------------------------
#
# Normalfall:
# - Ton und Bild sind an der Quelle grundsätzlich synchron.
#
# Problem in dieser Kette:
# - durch die H.265-Verarbeitung / Decoder-Probleme / Transcode-Kette
#   kann das Videobild relativ zum Ton zu spät erscheinen
#
# Lösung in diesem Skript:
# - das Video wird mit "setpts=PTS+..." künstlich verzögert
# - damit kann das Bild wieder passend zum Ton ausgerichtet werden
#
# Wichtige fachliche Grenze:
# - dieses Skript kann NUR das VIDEO verzögern
# - das Audio wird mit "-c:a copy" unverändert durchgereicht
# - eine Audio-Verzögerung ist hier NICHT vorgesehen
#
# setpts=PTS+X/TB bedeutet:
# - positiver Wert: Bild kommt später
# - Wert 0: keine zusätzliche Bildverzögerung
#
# Deshalb nur verwenden, wenn der TON nach dem Bild kommt.
# Dann kann das Bild künstlich nach hinten verschoben werden,
# bis Ton und Bild wieder zusammenpassen.
#
# Nicht geeignet, wenn das Bild bereits nach dem Ton kommt.
# Dafür müsste man das Audio verzögern, was dieses Skript nicht macht.
#
# Wichtiger Praxis-Hinweis:
# - VIDEO_DELAY behebt nicht die eigentliche Ursache
# - er kaschiert nur die sichtbare Asynchronität in dieser Pipeline
# - wenn sich Encoder, Decoder, Netzlast oder CPU-Last ändern,
#   kann später ein anderer Wert nötig sein
#
# Empfohlene Testschritte:
# - nur in kleinen Schritten ändern, z.B. 0.05
# - bei Showdown/Table-Tennis besonders vorsichtig testen,
#   da Ballkontakte akustisch und optisch sehr präzise wahrnehmbar sind
#
# -----------------------
# Encoding-/Output-Hinweis
# -----------------------
#
# - libx264 wird verwendet, weil YouTube-RTMP mit H.264 in dieser Kette
#   robuster funktioniert als H.265
# - preset veryfast ist ein Kompromiss aus CPU-Last und Qualität
# - tune zerolatency vermeidet zusätzliche Pufferung
# - pix_fmt yuv420p sorgt für breite Kompatibilität bei YouTube
#
# GOP / Keyframes:
# - g=100 bedeutet bei 50 fps einen Keyframe-Abstand von 2 Sekunden
# - sc_threshold=0 unterdrückt zusätzliche Szenenwechsel-Keyframes
# - Ziel: gleichmäßige, kontrollierte GOP-Struktur für stabileren Livebetrieb
#
# Audio:
# - -c:a copy übernimmt den Ton ohne Neukodierung
# - das spart CPU und vermeidet zusätzliche Fehlerquellen
# - Nachteil: Audio kann hier nicht per Filter verzögert oder bearbeitet werden

VIDEO_DELAY="0.15"

set -eu

# Lädt die Umgebungsvariablen für diesen Tisch-Stream:
# - RTSP_HOST
# - RTSP_PORT
# - TABLE
# - YOUTUBE_KEY
. /etc/ffmpeg-table.env

exec /usr/bin/ffmpeg \
  -rtsp_transport tcp \
  -i "rtsp://${RTSP_HOST}:${RTSP_PORT}/table${TABLE}" \
  -vf "setpts=PTS+${VIDEO_DELAY}/TB,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=/var/overlays/table${TABLE}.txt:reload=1:fontcolor=black@0:fontsize=34:line_spacing=5:box=1:boxcolor=lightblue@0.16:boxborderw=13:x=40:y=h-text_h-40,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=/var/overlays/table${TABLE}.txt:reload=1:fontcolor=white:fontsize=34:line_spacing=5:borderw=1:bordercolor=black@0.35:shadowx=1:shadowy=1:shadowcolor=black@0.22:box=1:boxcolor=black@0.32:boxborderw=10:x=40:y=h-text_h-40" \
  -c:v libx264 \
  -preset veryfast \
  -tune zerolatency \
  -pix_fmt yuv420p \
  -g 100 \
  -sc_threshold 0 \
  -c:a copy \
  -f flv \
  "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_KEY}"
