# MediaMTX ARM64 + camera publishers

Self-contained package: MediaMTX server + Astra / OAK stream scripts.

## Contents

| Path | Role |
|------|------|
| `mediamtx` | Server binary (linux arm64) |
| `mediamtx.yml` | Config (`/astra`, `/oak` on-demand) |
| `start.sh` | Run server from this directory |
| `stream/stream_astra_*` | Orbbec Astra Mini S capture + publish |
| `stream/build.sh` | Build `stream_astra_raw` |
| `stream/stream_oak_*` | Luxonis OAK capture + publish |
| `install.sh` | Optional host install helpers (nginx/cloudflared) |

## Dependencies (host)

- `ffmpeg`
- Astra: OrbbecSDK (`SDK_ROOT`, default `~/OrbbecSDK_arm64/...`), OpenCV, USB `2bc5:0407`
- OAK: `python3`, `depthai`, `opencv-python`, USB `03e7:*`

## Run

```bash
cd mediamtx_v1.20.0_linux_arm64
./stream/build.sh    # Astra binary (once)
./start.sh
```

- WebRTC: `http://<host>:8889/astra` or `/oak`
- RTSP: `rtsp://<host>:8554/astra`

Tune in `mediamtx.yml` → `paths.astra.runOnDemand` / `paths.oak.runOnDemand` (`ASTRA_*` / `OAK_*` env vars).
