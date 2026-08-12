#!/bin/bash
# Stream Orbbec Astra Mini S -> MediaMTX (RTSP path /astra)
# Sharp config: 640x480 @10fps MJPEG->H264 (avoids raw pipe desync).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK_ROOT="${SDK_ROOT:-$HOME/OrbbecSDK_arm64/OrbbecSDK_C_C++_v1.10.27_20250925_0549823_linux_arm64_release/OrbbecSDK_v1.10.27}"
BIN_DIR="$SDK_ROOT/Example/bin"
RAW="$ROOT/stream_astra_raw"

MODE="${ASTRA_MODE:-color}"
WIDTH="${ASTRA_WIDTH:-640}"
HEIGHT="${ASTRA_HEIGHT:-480}"
FPS="${ASTRA_FPS:-8}"
BITRATE="${ASTRA_BITRATE:-800k}"
ENCODER="${ASTRA_ENCODER:-libx264}"
MTX_HOST="${MTX_HOST:-127.0.0.1}"
MTX_PORT="${RTSP_PORT:-8554}"
PATH_NAME="${MTX_PATH:-astra}"
RTSP_URL="rtsp://${MTX_HOST}:${MTX_PORT}/${PATH_NAME}"
RTSP_TRANSPORT="${ASTRA_RTSP_TRANSPORT:-tcp}"

if [[ ! -x "$RAW" ]]; then
  echo "Missing $RAW — build first: $ROOT/build_astra_stream.sh" >&2
  exit 1
fi

if ! lsusb -d 2bc5:0407 >/dev/null 2>&1; then
  echo "Astra Mini S (2bc5:0407) not found on USB" >&2
  exit 1
fi

export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

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
echo "Publishing Astra ($MODE) -> $RTSP_URL (${WIDTH}x${HEIGHT}@${FPS}, enc=$ENC, br=$BITRATE, rtsp=$RTSP_TRANSPORT, pipe=mjpeg)" >&2

FFMPEG_ENC_ARGS=()
if [[ "$ENC" == "h264_v4l2m2m" ]]; then
  FFMPEG_ENC_ARGS=(
    -c:v h264_v4l2m2m -b:v "$BITRATE"
    -force_key_frames "expr:gte(t,n_forced*0.5)"
  )
else
  FFMPEG_ENC_ARGS=(
    -c:v libx264 -preset ultrafast -tune zerolatency -threads 2
    -pix_fmt yuv420p
    -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize "$BITRATE"
    -g "$FPS" -keyint_min "$FPS" -sc_threshold 0 -bf 0 -refs 1
    -x264-params "rc-lookahead=0:sync-lookahead=0:bframes=0:b-adapt=0:sliced-threads=0:mbtree=0:aud=1:repeat-headers=1:slice-max-size=1000"
  )
fi

exec "$RAW" --mode "$MODE" --width "$WIDTH" --height "$HEIGHT" --fps "$FPS" \
  | ffmpeg -hide_banner -loglevel warning \
      -fflags +genpts -flags low_delay \
      -f mjpeg -framerate "$FPS" -i - \
      -an -vf "scale=${WIDTH}:${HEIGHT}:flags=fast_bilinear" \
      "${FFMPEG_ENC_ARGS[@]}" \
      -f rtsp -rtsp_transport "$RTSP_TRANSPORT" \
      "$RTSP_URL"
