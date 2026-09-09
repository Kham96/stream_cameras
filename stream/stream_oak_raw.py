#!/usr/bin/env python3
"""Capture Luxonis OAK (DepthAI) RGB and write BGR24 frames to stdout for ffmpeg/MediaMTX."""
from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime

import cv2
import depthai as dai
import numpy as np


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=360)
    p.add_argument("--fps", type=float, default=15.0)
    p.add_argument("--sensor", choices=["720p", "800p", "1080p"], default="720p")
    return p.parse_args()


def sensor_res(name: str):
    m = {
        "720p": dai.ColorCameraProperties.SensorResolution.THE_720_P,
        "800p": dai.ColorCameraProperties.SensorResolution.THE_800_P,
        "1080p": dai.ColorCameraProperties.SensorResolution.THE_1080_P,
    }
    return m[name]


def draw_clock(bgr: np.ndarray) -> None:
    text = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    scale = max(0.4, bgr.shape[1] / 640.0 * 0.55)
    thickness = max(1, int(scale * 2))
    (tw, th), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, thickness)
    org = (8, 8 + th)
    cv2.rectangle(
        bgr,
        (org[0] - 4, org[1] - th - 4),
        (org[0] + tw + 4, org[1] + baseline + 4),
        (0, 0, 0),
        -1,
    )
    cv2.putText(bgr, text, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 255, 0), thickness, cv2.LINE_AA)


def open_device(pipeline: dai.Pipeline) -> dai.Device:
    """Open OAK; prefer USB2 HIGH if SuperSpeed unavailable (Pi hub)."""
    infos = dai.Device.getAllAvailableDevices()
    if not infos:
        raise RuntimeError("No OAK / MyriadX device found (lsusb -d 03e7:)")

    info = infos[0]
    print(
        f"OAK found mxid={info.getMxId()} state={info.state} name={info.name}",
        file=sys.stderr,
        flush=True,
    )

    last_err: Exception | None = None
    for speed in (dai.UsbSpeed.HIGH, dai.UsbSpeed.SUPER):
        try:
            print(f"Opening with maxUsbSpeed={speed} ...", file=sys.stderr, flush=True)
            return dai.Device(pipeline, info, maxUsbSpeed=speed)
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"open failed ({speed}): {e}", file=sys.stderr, flush=True)
            time.sleep(2.0)
            # refresh device list after boot/re-enum
            infos = dai.Device.getAllAvailableDevices()
            if infos:
                info = infos[0]

    raise RuntimeError(
        f"Cannot open OAK after boot: {last_err}. "
        "Plug OAK into a USB3 (blue) port directly — not through a USB2 hub."
    )


def main() -> int:
    args = parse_args()
    out_w, out_h = args.width, args.height
    fps = max(1.0, args.fps)
    period = 1.0 / fps

    pipeline = dai.Pipeline()
    cam = pipeline.create(dai.node.ColorCamera)
    cam.setBoardSocket(dai.CameraBoardSocket.CAM_A)
    cam.setResolution(sensor_res(args.sensor))
    cam.setFps(fps)
    cam.setInterleaved(False)
    cam.setColorOrder(dai.ColorCameraProperties.ColorOrder.BGR)
    # Keep ISP output near target size to reduce Pi CPU.
    cam.setPreviewSize(out_w, out_h)
    cam.setVideoSize(out_w, out_h)

    xout = pipeline.create(dai.node.XLinkOut)
    xout.setStreamName("rgb")
    cam.video.link(xout.input)

    device = open_device(pipeline)
    print(
        f"OAK_STREAM out={out_w}x{out_h} fps={fps} usb={device.getUsbSpeed()} "
        f"name={device.getDeviceName()}",
        file=sys.stderr,
        flush=True,
    )

    q = device.getOutputQueue("rgb", maxSize=4, blocking=False)
    next_due = time.monotonic()
    try:
        while True:
            pkt = q.tryGet()
            if pkt is None:
                time.sleep(0.001)
                continue
            now = time.monotonic()
            if now < next_due:
                continue
            next_due = now + period

            bgr = pkt.getCvFrame()
            if bgr is None or bgr.size == 0:
                continue
            if bgr.shape[1] != out_w or bgr.shape[0] != out_h:
                bgr = cv2.resize(bgr, (out_w, out_h), interpolation=cv2.INTER_AREA)
            if not bgr.flags["C_CONTIGUOUS"]:
                bgr = np.ascontiguousarray(bgr)

            draw_clock(bgr)
            try:
                sys.stdout.buffer.write(bgr.tobytes())
                sys.stdout.buffer.flush()
            except BrokenPipeError:
                break
    finally:
        device.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:  # noqa: BLE001
        print(f"OAK error: {e}", file=sys.stderr, flush=True)
        raise SystemExit(1)
