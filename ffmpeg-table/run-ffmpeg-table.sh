#!/bin/sh

/usr/local/bin/run-ffmpeg-table.sh

set -eu

. /etc/ffmpeg-table.env

exec /usr/bin/ffmpeg \
  -rtsp_transport tcp \
  -i "rtsp://${RTSP_HOST}:${RTSP_PORT}/table${TABLE}" \
  -vf "setpts=PTS+0.15/TB,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=/var/overlays/table${TABLE}.txt:reload=1:fontcolor=black@0:fontsize=34:line_spacing=5:box=1:boxcolor=lightblue@0.16:boxborderw=13:x=40:y=h-text_h-40,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:textfile=/var/overlays/table${TABLE}.txt:reload=1:fontcolor=white:fontsize=34:line_spacing=5:borderw=1:bordercolor=black@0.35:shadowx=1:shadowy=1:shadowcolor=black@0.22:box=1:boxcolor=black@0.32:boxborderw=10:x=40:y=h-text_h-40" \
  -c:v libx264 \
  -preset veryfast \
  -tune zerolatency \
  -pix_fmt yuv420p \
  -g 100 \
  -sc_threshold 0 \
  -c:a copy \
  -f flv \
  "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_KEY}"
