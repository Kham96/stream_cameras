import asyncio
import cv2
import numpy as np
from livekit import rtc

LIVEKIT_URL = "ws://192.168.1.15:7880"
DRONE_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoicmFzcGJlcnJ5LXBpLWRyb25lIiwidmlkZW8iOnsicm9vbUpvaW4iOnRydWUsInJvb20iOiJkcm9uZS1yb29tIiwiY2FuUHVibGlzaCI6dHJ1ZSwiY2FuU3Vic2NyaWJlIjp0cnVlLCJjYW5QdWJsaXNoRGF0YSI6dHJ1ZX0sInN1YiI6InJhc3BiZXJyeS1waS1kcm9uZSIsImlzcyI6ImRldmtleSIsIm5iZiI6MTc4NjQwNTM3MiwiZXhwIjoxNzg2NDI2OTcyfQ.6EdEzq6_8a5zZjfCEFCAuTbmX-xPlsBxQ4Jb4m6bzjc"

async def main():
    room = rtc.Room()
    print("Đang kết nối tới LiveKit SFU...")
    await room.connect(LIVEKIT_URL, DRONE_TOKEN)
    print("Đã kết nối thành công!")

    width, height = 640, 480
    source = rtc.VideoSource(width, height)
    track = rtc.LocalVideoTrack.create_video_track("drone-cam", source)
    
    options = rtc.TrackPublishOptions(
        source=rtc.TrackSource.SOURCE_CAMERA,
        simulcast=False
    )
    publication = await room.local_participant.publish_track(track, options)
    print("Video Track đã publish thành công!")

    cap = cv2.VideoCapture(0)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    try:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                print("Không đọc được frame từ Camera!")
                await asyncio.sleep(0.1)
                continue

            # Resize đúng kích thước nếu camera trả về lệch size
            if frame.shape[1] != width or frame.shape[0] != height:
                frame = cv2.resize(frame, (width, height))

            # Chuyển BGR sang RGBA và ÉP LIÊN TỤC VÙNG NHỚ (np.ascontiguousarray)
            rgba_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGBA)
            rgba_frame = np.ascontiguousarray(rgba_frame, dtype=np.uint8)

            # Khởi tạo Buffer bằng create_video_frame chuẩn Rust Binding
            argb_frame = rtc.ArgbFrame.create(
                rtc.VideoFormat.RGBA, 
                width, 
                height, 
                rgba_frame.data
            )
            
            video_frame = rtc.VideoFrame(argb_frame)
            source.capture_frame(video_frame)
            
            await asyncio.sleep(0.033) # ~30 FPS

    except Exception as e:
        print(f"Lỗi khi push stream: {e}")
    finally:
        cap.release()
        await room.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
