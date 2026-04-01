#!/bin/sh

# /usr/local/bin/run-ffmpeg-table.sh
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
#
# Transport-Hinweis:
# - RTSP wird hier bewusst über TCP gelesen, um die Strecke stabiler
#   gegen Paketverluste und Jitter zu machen
#
# ---------------------------
# WICHTIG ZUR AV-SYNCHRONITÄT
# ---------------------------
# Normalfall:
# - Ton und Bild sind an der Quelle grundsätzlich synchron.
#
# Problem in dieser Kette:
# - durch die H.265-Verarbeitung / Decoder-Probleme / Transcode-Kette
#   kann das Videobild relativ zum Ton zu spät erscheinen.
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
