# stream_cameras — MediaMTX ARM64 + Astra / OAK

Gói sẵn trên **Linux ARM64** (Raspberry Pi / robot): [MediaMTX](https://github.com/bluenviron/mediamtx) v1.20.0 + publisher cho **Orbbec Astra Mini S** và **Luxonis OAK**.

Repo: [Kham96/stream_cameras](https://github.com/Kham96/stream_cameras)

Một server MediaMTX (`mediamtx.yml`) phục vụ **hai path**: `/astra` và `/oak`. Camera **chỉ bật khi có người xem** (`runOnDemand`).

---

## Cấu trúc

```
.
├── mediamtx                 # Binary MediaMTX v1.20.0 (linux arm64)
├── mediamtx.yml             # Config — path /astra và /oak
├── start.sh                 # Khởi động MediaMTX từ thư mục này
├── stream/
│   ├── build.sh             # Build stream_astra_raw
│   ├── stream_astra_raw.cpp
│   ├── stream_astra_to_mediamtx.sh
│   ├── stream_oak_raw.py
│   └── stream_oak_to_mediamtx.sh
├── install.sh               # Tuỳ chọn: nginx + cloudflared
└── LICENSE
```

Luôn chạy `./start.sh` **trong thư mục repo này** — `runOnDemand` dùng path tương đối `./stream/...`.

---

## Yêu cầu

| Thành phần | Cần có |
|------------|--------|
| OS | Linux **arm64** |
| Chung | `ffmpeg`, camera USB đã cắm |
| **Astra** | OrbbecSDK, OpenCV (`libopencv-*`, header `/usr/include/opencv4`), `g++` (khi build), USB `2bc5:0407` |
| **OAK** | `python3`, `depthai`, OpenCV (`opencv-python` hoặc `libopencv-*`), USB `03e7:*` |

OrbbecSDK mặc định:

```text
~/OrbbecSDK_arm64/OrbbecSDK_C_C++_v1.10.27_.../OrbbecSDK_v1.10.27
```

Đổi bằng biến `SDK_ROOT` nếu SDK nằm chỗ khác.

Kiểm tra camera:

```bash
lsusb -d 2bc5:0407  # Astra Mini S
lsusb -d 03e7:      # OAK / MyriadX
```

---

## Chạy

```bash
git clone git@github.com:Kham96/stream_cameras.git
cd stream_cameras

# Build Astra một lần (start.sh cũng tự build nếu thiếu binary)
./stream/build.sh

./start.sh
```

Mở trình duyệt hoặc VLC khi cần xem — publisher chỉ chạy lúc có viewer.

---

## URL xem stream

Thay `<host>` bằng IP máy (LAN) hoặc domain.

| Giao thức | Astra | OAK |
|-----------|-------|-----|
| **WebRTC** | `http://<host>:8889/astra` | `http://<host>:8889/oak` |
| **RTSP** | `rtsp://<host>:8554/astra` | `rtsp://<host>:8554/oak` |
| **HLS** | `http://<host>:8891/astra` | `http://<host>:8891/oak` |

Ví dụ:

```bash
ffplay -rtsp_transport tcp rtsp://127.0.0.1:8554/astra
ffplay -rtsp_transport tcp rtsp://127.0.0.1:8554/oak
```

---

## Chất lượng stream

Sửa `mediamtx.yml` → `paths.astra.runOnDemand` / `paths.oak.runOnDemand`.

### Astra (mặc định)

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `ASTRA_MODE` | `color` | `color` hoặc `depth` |
| `ASTRA_WIDTH` / `ASTRA_HEIGHT` | `640` / `480` | Độ phân giải |
| `ASTRA_FPS` | `8` | FPS |
| `ASTRA_BITRATE` | `800k` | Bitrate H.264 |

### OAK (mặc định trong yml)

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `OAK_WIDTH` / `OAK_HEIGHT` | `640` / `360` | Preview / output |
| `OAK_FPS` | `10` | FPS |
| `OAK_BITRATE` | `800k` | Bitrate H.264 |
| `OAK_SENSOR` | (script: `720p`) | `720p` / `800p` / `1080p` |

Ví dụ ổn định hơn qua Internet:

```yaml
runOnDemand: env ASTRA_MODE=color ASTRA_WIDTH=640 ASTRA_HEIGHT=480 ASTRA_FPS=8 ASTRA_BITRATE=600k ./stream/stream_astra_to_mediamtx.sh
```

Sau khi sửa: MediaMTX thường tự reload. Nếu không: Ctrl+C rồi `./start.sh` lại.

---

## Cổng

| Cổng | Dịch vụ |
|------|---------|
| `8554` | RTSP |
| `8889` | WebRTC (HTTP) |
| `8888` | WebRTC ICE TCP |
| `8189` | WebRTC ICE UDP |
| `8891` | HLS |
| `1935` | RTMP |

Xem từ ngoài LAN: mở firewall / port-forward. Có thể dùng `./install.sh` (nginx + cloudflared) rồi cấu hình tunnel thủ công.

WebRTC: chỉnh `webrtcAdditionalHosts` trong `mediamtx.yml` (IP LAN / public) để ICE nhận đúng host.

---

## Lưu ý

1. Cắm camera trước khi mở URL xem — publisher kiểm tra USB khi `runOnDemand`.
2. Log `reader is too slow, discarding N frames` → hạ `*_BITRATE` / `*_FPS`, hoặc xem trong LAN.
3. `writeQueueSize: 512` giúp đỡ drop trên WAN hơn queue nhỏ.
4. File `auto.crt` / `auto.key` / `Log/` / `*.log` **không** commit (xem `.gitignore`).

---

## Build lại Astra

```bash
./stream/build.sh
```

Cần `g++`, OpenCV headers, và OrbbecSDK tại `SDK_ROOT`.

---

## License

Xem `LICENSE` (MediaMTX upstream). Script camera trong `stream/` đi kèm repo này.
