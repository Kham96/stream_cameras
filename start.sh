#!/bin/bash
# Start MediaMTX from this package directory (required so ./stream paths work).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -x ./mediamtx ]]; then
  echo "Missing ./mediamtx binary" >&2
  exit 1
fi
if [[ ! -f ./mediamtx.yml ]]; then
  echo "Missing ./mediamtx.yml" >&2
  exit 1
fi
if [[ ! -x ./stream/stream_astra_raw ]]; then
  echo "Building Astra capture binary..." >&2
  ./stream/build.sh
fi

echo "MediaMTX root: $ROOT"
echo "  WebRTC astra: http://<host>:8889/astra"
echo "  WebRTC oak:   http://<host>:8889/oak"
echo "  RTSP:         rtsp://<host>:8554/{astra,oak}"
exec ./mediamtx ./mediamtx.yml
