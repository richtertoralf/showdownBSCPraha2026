#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/event.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Deployment-Datei fehlt: ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

for required in MEDIAMTX_HOST RTSP_PORT YOUTUBE_URL; do
  if [[ -z "${!required:-}" ]]; then
    echo "Pflichtwert fehlt in event.env: ${required}" >&2
    exit 1
  fi
done

umask 077
config_file="$(mktemp)"
trap 'rm -f "${config_file}"' EXIT

configured=0

for index in {1..99}; do
  host_var="FFMPEG${index}_HOST"
  table_var="FFMPEG${index}_TABLE"
  key_var="FFMPEG${index}_KEY"
  delay_var="FFMPEG${index}_VIDEO_DELAY"

  host="${!host_var:-}"
  [[ -n "${host}" ]] || continue

  table="${!table_var:-}"
  key="${!key_var:-}"
  delay="${!delay_var:-}"

  for value_name in table key delay; do
    if [[ -z "${!value_name}" ]]; then
      echo "Konfiguration für ${host_var} ist unvollständig: ${value_name}" >&2
      exit 1
    fi
  done

  printf '%s\n' \
    "TABLE=${table}" \
    "MEDIAMTX_HOST=${MEDIAMTX_HOST}" \
    "RTSP_PORT=${RTSP_PORT}" \
    "YOUTUBE_URL=${YOUTUBE_URL}" \
    "YOUTUBE_KEY=${key}" \
    "VIDEO_DELAY=${delay}" >"${config_file}"

  echo "Konfiguriere FFmpeg-Server ${index} (${host})"
  scp -q "${config_file}" "root@${host}:/root/.ffmpeg-table.env.deploy"
  ssh "root@${host}" \
    'install -o root -g root -m 0600 /root/.ffmpeg-table.env.deploy /etc/ffmpeg-table.env && rm -f /root/.ffmpeg-table.env.deploy && systemctl enable ffmpeg-table && systemctl restart ffmpeg-table && systemctl --no-pager --full status ffmpeg-table'

  configured=$((configured + 1))
done

if (( configured == 0 )); then
  echo "Keine FFMPEGn_HOST-Einträge in event.env gefunden." >&2
  exit 1
fi
