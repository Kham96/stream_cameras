#!/bin/bash
# Stream Luxonis OAK (DepthAI / MyriadX) -> MediaMTX (RTSP path /oak)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RAW="$ROOT/stream_oak_raw.py"

WIDTH="${OAK_WIDTH:-640}"
HEIGHT="${OAK_HEIGHT:-360}"
FPS="${OAK_FPS:-15}"
BITRATE="${OAK_BITRATE:-800k}"
ENCODER="${OAK_ENCODER:-libx264}"
SENSOR="${OAK_SENSOR:-720p}"
MTX_HOST="${MTX_HOST:-127.0.0.1}"
MTX_PORT="${RTSP_PORT:-8554}"
PATH_NAME="${MTX_PATH:-oak}"
RTSP_URL="rtsp://${MTX_HOST}:${MTX_PORT}/${PATH_NAME}"
RTSP_TRANSPORT="${OAK_RTSP_TRANSPORT:-tcp}"

if [[ ! -f "$RAW" ]]; then
  echo "Missing $RAW" >&2
  exit 1
fi

if ! lsusb -d 03e7: >/dev/null 2>&1; then
  echo "OAK / MyriadX (03e7:*) not found on USB" >&2
  exit 1
fi

pick_encoder() {
  if [[ "$ENCODER" != "auto" ]]; then
    echo "$ENCODER"
    return
  fi
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_v4l2m2m'; then
    echo "h264_v4l2m2m"
  else
    echo "libx264"
  fi
}

ENC="$(pick_encoder)"
echo "Publishing OAK -> $RTSP_URL (${WIDTH}x${HEIGHT}@${FPS}, enc=$ENC, br=$BITRATE, sensor=$SENSOR)" >&2

FFMPEG_ENC_ARGS=()
if [[ "$ENC" == "h264_v4l2m2m" ]]; then
  FFMPEG_ENC_ARGS=(
    -c:v h264_v4l2m2m -b:v "$BITRATE"
    -force_key_frames "expr:gte(t,n_forced*0.5)"
  )
else
  FFMPEG_ENC_ARGS=(
    -c:v libx264 -preset ultrafast -tune zerolatency -threads 1
    -pix_fmt yuv420p
    -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize 150k
    -g "$FPS" -keyint_min "$FPS" -sc_threshold 0 -bf 0 -refs 1
    -x264-params "rc-lookahead=0:sync-lookahead=0:bframes=0:b-adapt=0:sliced-threads=0:mbtree=0:aud=1:repeat-headers=1"
  )
fi

exec python3 -u "$RAW" --width "$WIDTH" --height "$HEIGHT" --fps "$FPS" --sensor "$SENSOR" \
  | ffmpeg -hide_banner -loglevel warning \
      -fflags nobuffer+flush_packets -flags low_delay \
      -probesize 32 -analyzeduration 0 \
      -f rawvideo -pix_fmt bgr24 -s "${WIDTH}x${HEIGHT}" -r "$FPS" -i - \
      -an -flush_packets 1 -muxdelay 0 -muxpreload 0 \
      "${FFMPEG_ENC_ARGS[@]}" \
      -f rtsp -rtsp_transport "$RTSP_TRANSPORT" \
      "$RTSP_URL"
