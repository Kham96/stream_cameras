// Capture Orbbec Astra Mini S and write BGR24 frames to stdout for ffmpeg/MediaMTX.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include "libobsensor/ObSensor.hpp"

namespace {

cv::Mat depthToBgr(std::shared_ptr<ob::DepthFrame> depthFrame) {
    cv::Mat raw(depthFrame->height(), depthFrame->width(), CV_16UC1, depthFrame->data());
    float scale = depthFrame->getValueScale();
    cv::Mat truncated;
    cv::threshold(raw, truncated, 5120.0f / scale, 0, cv::THRESH_TRUNC);
    cv::Mat gray8;
    truncated.convertTo(gray8, CV_8UC1, scale * 0.05);
    cv::Mat bgr;
    cv::applyColorMap(gray8, bgr, cv::COLORMAP_JET);
    bgr.setTo(cv::Scalar(0, 0, 0), raw == 0);
    return bgr;
}

cv::Mat boostIfDark(cv::Mat bgr) {
    if (bgr.empty()) {
        return bgr;
    }
    cv::Scalar mean = cv::mean(bgr);
    double m = (mean[0] + mean[1] + mean[2]) / 3.0;
    if (m > 0.0 && m < 40.0) {
        double gain = std::min(255.0 / (m * 4.0), 16.0);
        bgr.convertTo(bgr, -1, gain, 0);
    }
    return bgr;
}

cv::Mat colorToBgr(std::shared_ptr<ob::ColorFrame> colorFrame) {
    cv::Mat bgr;
    auto fmt = colorFrame->format();
    const int w = static_cast<int>(colorFrame->width());
    const int h = static_cast<int>(colorFrame->height());
    const size_t nbytes = colorFrame->dataSize();
    const size_t expect2 = static_cast<size_t>(w) * static_cast<size_t>(h) * 2;
    const size_t expect3 = static_cast<size_t>(w) * static_cast<size_t>(h) * 3;

    // Copy payload immediately — SDK may reuse the frame buffer on the next waitForFrames.
    cv::Mat payload(1, static_cast<int>(nbytes), CV_8UC1);
    std::memcpy(payload.data, colorFrame->data(), nbytes);

    static bool logged = false;
    if (!logged) {
        std::cerr << "color fmt=" << static_cast<int>(fmt) << " " << w << "x" << h
                  << " dataSize=" << nbytes << std::endl;
        logged = true;
    }

    // Default Astra Mini S color is UYVY; if payload is 2bpp, decode as UYVY.
    if (nbytes == expect2 && fmt != OB_FORMAT_YUYV && fmt != OB_FORMAT_YUY2 &&
        fmt != OB_FORMAT_UYVY) {
        fmt = OB_FORMAT_UYVY;
    }

    if ((fmt == OB_FORMAT_RGB || fmt == OB_FORMAT_RGB888) && nbytes >= expect3) {
        cv::Mat rgb(h, w, CV_8UC3, payload.data);
        cv::cvtColor(rgb, bgr, cv::COLOR_RGB2BGR);
    } else if (fmt == OB_FORMAT_BGR && nbytes >= expect3) {
        bgr = cv::Mat(h, w, CV_8UC3, payload.data).clone();
    } else if (fmt == OB_FORMAT_YUYV || fmt == OB_FORMAT_YUY2) {
        cv::Mat raw(h, w, CV_8UC2, payload.data);
        cv::cvtColor(raw, bgr, cv::COLOR_YUV2BGR_YUY2);
    } else if (fmt == OB_FORMAT_UYVY) {
        cv::Mat raw(h, w, CV_8UC2, payload.data);
        cv::cvtColor(raw, bgr, cv::COLOR_YUV2BGR_UYVY);
    } else if (fmt == OB_FORMAT_I420) {
        cv::Mat raw(h * 3 / 2, w, CV_8UC1, payload.data);
        cv::cvtColor(raw, bgr, cv::COLOR_YUV2BGR_I420);
    } else if (fmt == OB_FORMAT_NV12) {
        cv::Mat raw(h * 3 / 2, w, CV_8UC1, payload.data);
        cv::cvtColor(raw, bgr, cv::COLOR_YUV2BGR_NV12);
    } else if (fmt == OB_FORMAT_NV21) {
        cv::Mat raw(h * 3 / 2, w, CV_8UC1, payload.data);
        cv::cvtColor(raw, bgr, cv::COLOR_YUV2BGR_NV21);
    } else if (fmt == OB_FORMAT_Y16) {
        cv::Mat raw(h, w, CV_16UC1, payload.data);
        cv::Mat gray8;
        raw.convertTo(gray8, CV_8UC1, 1.0 / 16.0);
        cv::cvtColor(gray8, bgr, cv::COLOR_GRAY2BGR);
    } else if (fmt == OB_FORMAT_MJPG) {
        bgr = cv::imdecode(payload, cv::IMREAD_COLOR);
    } else if (nbytes >= expect2 && nbytes < expect2 + static_cast<size_t>(h)) {
        cv::Mat raw(h, w, CV_8UC2, payload.data);
        cv::cvtColor(raw, bgr, cv::COLOR_YUV2BGR_UYVY);
    } else if (nbytes >= expect3) {
        bgr = cv::Mat(h, w, CV_8UC3, payload.data).clone();
        std::cerr << "Unknown color fmt=" << static_cast<int>(fmt) << ", treating as BGR\n";
    }
    return boostIfDark(bgr);
}

void usage(const char *argv0) {
    std::cerr << "Usage: " << argv0
              << " [--mode depth|color] [--width OUT_W] [--height OUT_H] [--fps N]\n";
}

void drawRealtimeClock(cv::Mat &bgr) {
    using clock = std::chrono::system_clock;
    const auto now = clock::now();
    const std::time_t t = clock::to_time_t(now);
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;

    std::tm tm_local{};
    localtime_r(&t, &tm_local);

    std::ostringstream oss;
    oss << std::put_time(&tm_local, "%Y-%m-%d %H:%M:%S") << '.' << std::setw(3) << std::setfill('0')
        << ms.count();
    const std::string text = oss.str();

    const double scale = std::max(0.45, bgr.cols / 320.0 * 0.55);
    const int thickness = std::max(1, static_cast<int>(scale * 2));
    int baseline = 0;
    const cv::Size sz = cv::getTextSize(text, cv::FONT_HERSHEY_SIMPLEX, scale, thickness, &baseline);
    const cv::Point org(8, 8 + sz.height);

    cv::rectangle(
        bgr,
        cv::Point(org.x - 4, org.y - sz.height - 4),
        cv::Point(org.x + sz.width + 4, org.y + baseline + 4),
        cv::Scalar(0, 0, 0),
        cv::FILLED);
    cv::putText(bgr, text, org, cv::FONT_HERSHEY_SIMPLEX, scale, cv::Scalar(0, 255, 0), thickness, cv::LINE_AA);
}

}  // namespace

int main(int argc, char **argv) try {
    std::string mode = "color";
    int out_w = 320;
    int out_h = 240;
    double fps = 15.0;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--mode" && i + 1 < argc) {
            mode = argv[++i];
        } else if (a == "--width" && i + 1 < argc) {
            out_w = std::stoi(argv[++i]);
        } else if (a == "--height" && i + 1 < argc) {
            out_h = std::stoi(argv[++i]);
        } else if (a == "--fps" && i + 1 < argc) {
            fps = std::stod(argv[++i]);
        } else if (a == "-h" || a == "--help") {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    if (mode != "depth" && mode != "color") {
        std::cerr << "mode must be depth or color\n";
        return 1;
    }
    if (fps < 1.0) {
        fps = 1.0;
    }

    ob::Pipeline pipe;
    auto config = std::make_shared<ob::Config>();
    const ob_sensor_type sensor =
        (mode == "depth") ? OB_SENSOR_DEPTH : OB_SENSOR_COLOR;

    auto dumpProfiles = [&](const std::shared_ptr<ob::StreamProfileList> &list) {
        const uint32_t n = list->count();
        std::cerr << "ASTRA_STREAM available " << (mode == "depth" ? "depth" : "color")
                  << " profiles (" << n << "):\n";
        for (uint32_t i = 0; i < n; ++i) {
            auto p = list->getProfile(i)->as<ob::VideoStreamProfile>();
            std::cerr << "  [" << i << "] " << p->width() << "x" << p->height()
                      << " @" << p->fps() << " fmt=" << static_cast<int>(p->format()) << "\n";
        }
    };

    try {
        auto profiles = pipe.getStreamProfileList(sensor);
        dumpProfiles(profiles);

        std::shared_ptr<ob::VideoStreamProfile> chosen;
        const int want_fps = static_cast<int>(fps);
        // Prefer RGB888 (fmt 22) so we avoid packed UYVY decode tearing/misalign.
        const std::pair<int, int> sizes[] = {
            {out_w, out_h},
            {640, 480},
            {1280, 960},
            {OB_WIDTH_ANY, OB_HEIGHT_ANY},
        };
        const OBFormat formats[] = {OB_FORMAT_RGB, OB_FORMAT_UYVY, OB_FORMAT_YUYV, OB_FORMAT_ANY};
        const int fpss[] = {want_fps, 30, OB_FPS_ANY};

        for (const auto &wh : sizes) {
            for (OBFormat fmt : formats) {
                for (int f : fpss) {
                    try {
                        chosen = profiles->getVideoStreamProfile(wh.first, wh.second, fmt, f);
                        break;
                    } catch (ob::Error &) {
                    }
                }
                if (chosen) {
                    break;
                }
            }
            if (chosen) {
                break;
            }
        }
        if (!chosen) {
            throw std::runtime_error("no matching video profile");
        }
        std::cerr << "ASTRA_STREAM capture profile "
                  << chosen->width() << "x" << chosen->height()
                  << " @" << chosen->fps()
                  << " fmt=" << static_cast<int>(chosen->format()) << "\n";
        config->enableStream(chosen);
        pipe.start(config);
    } catch (ob::Error &e) {
        std::cerr << "ASTRA_STREAM profile select failed: " << e.getMessage()
                  << " — using SDK default\n";
        config = std::make_shared<ob::Config>();
        config->enableVideoStream(mode == "depth" ? OB_STREAM_DEPTH : OB_STREAM_COLOR);
        pipe.start(config);
    } catch (const std::exception &e) {
        std::cerr << "ASTRA_STREAM profile select failed: " << e.what()
                  << " — using SDK default\n";
        config = std::make_shared<ob::Config>();
        config->enableVideoStream(mode == "depth" ? OB_STREAM_DEPTH : OB_STREAM_COLOR);
        pipe.start(config);
    }

    const auto frame_period = std::chrono::duration<double>(1.0 / fps);
    auto next_due = std::chrono::steady_clock::now();

    std::cerr << "ASTRA_STREAM mode=" << mode << " out=" << out_w << "x" << out_h
              << " fps=" << fps << std::endl;

    setvbuf(stdout, nullptr, _IONBF, 0);

    while (true) {
        auto frameset = pipe.waitForFrames(100);
        if (frameset == nullptr) {
            continue;
        }

        auto now = std::chrono::steady_clock::now();
        if (now < next_due) {
            continue;
        }
        next_due = now + std::chrono::duration_cast<std::chrono::steady_clock::duration>(frame_period);

        cv::Mat bgr;
        if (mode == "depth") {
            auto depth = frameset->depthFrame();
            if (depth == nullptr) {
                continue;
            }
            bgr = depthToBgr(depth);
        } else {
            auto color = frameset->colorFrame();
            if (color == nullptr) {
                continue;
            }
            bgr = colorToBgr(color);
            if (bgr.empty()) {
                continue;
            }
        }

        if (bgr.cols != out_w || bgr.rows != out_h) {
            cv::Mat resized;
            const int interp =
                (bgr.cols * bgr.rows > out_w * out_h) ? cv::INTER_AREA : cv::INTER_LINEAR;
            cv::resize(bgr, resized, cv::Size(out_w, out_h), 0, 0, interp);
            bgr = resized;
        }

        drawRealtimeClock(bgr);

        if (!bgr.isContinuous()) {
            bgr = bgr.clone();
        }

        // MJPEG keeps frame boundaries — raw BGR pipes desync into half-frame wraps.
        std::vector<uchar> jpeg;
        static const std::vector<int> jpeg_params = {cv::IMWRITE_JPEG_QUALITY, 85};
        if (!cv::imencode(".jpg", bgr, jpeg, jpeg_params)) {
            continue;
        }
        if (fwrite(jpeg.data(), 1, jpeg.size(), stdout) != jpeg.size()) {
            break;
        }
    }

    pipe.stop();
    return 0;
} catch (ob::Error &e) {
    std::cerr << "Orbbec error: " << e.getMessage() << std::endl;
    return 1;
} catch (const std::exception &e) {
    std::cerr << "Error: " << e.what() << std::endl;
    return 1;
}
