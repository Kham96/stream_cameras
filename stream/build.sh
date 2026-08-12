#!/bin/bash
# Build stream_astra_raw (Orbbec Astra Mini S -> stdout MJPEG/BGR for ffmpeg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK_ROOT="${SDK_ROOT:-$HOME/OrbbecSDK_arm64/OrbbecSDK_C_C++_v1.10.27_20250925_0549823_linux_arm64_release/OrbbecSDK_v1.10.27}"
BIN_DIR="$SDK_ROOT/Example/bin"
INC_DIR="$SDK_ROOT/SDK/include"

g++ -O2 -std=c++17 \
  "$ROOT/stream_astra_raw.cpp" \
  -o "$ROOT/stream_astra_raw" \
  -I"$INC_DIR" -I/usr/include/opencv4 \
  /usr/lib/aarch64-linux-gnu/libopencv_imgcodecs.so \
  /usr/lib/aarch64-linux-gnu/libopencv_imgproc.so \
  /usr/lib/aarch64-linux-gnu/libopencv_core.so \
  -L"$BIN_DIR" -lOrbbecSDK \
  -Wl,-rpath,"$BIN_DIR"

chmod +x "$ROOT/stream_astra_raw" "$ROOT/stream_astra_to_mediamtx.sh"
echo "Built: $ROOT/stream_astra_raw"
