#include <atomic>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <mutex>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libswscale/swscale.h>
}

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#elif defined(__APPLE__)
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

#if PHONECAM_WITH_SOFTCAM
#include <softcam/softcam.h>
#endif

#include "phonecam_client.h"
#include "control_parser.h"
#include "discovery.h"

namespace {

constexpr int kDiscoveryPort = 47821;

struct Frame {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> bgr;
};

struct ReceiverStatus {
  std::string state = "starting";
  std::string target;
  int width = 0;
  int height = 0;
  int64_t frames = 0;
  double avgFps = 0.0;
  double incomingMbps = 0.0;
  int64_t decodeErrors = 0;
};

class FrameSink {
public:
  virtual ~FrameSink() = default;
  virtual bool start(int width, int height, float fps) = 0;
  virtual bool send(const Frame& frame) = 0;
  virtual void updateStatus(const ReceiverStatus&) {}
};

class NullSink final : public FrameSink {
public:
  bool start(int width, int height, float fps) override {
    std::cout << "Headless/null sink active: " << width << "x" << height << " @ " << fps << " fps\n";
    return true;
  }

  bool send(const Frame&) override {
    return true;
  }
};

#if defined(_WIN32)
class PreviewSink final : public FrameSink {
public:
  bool start(int width, int height, float) override {
    width_ = width;
    height_ = height;

    WNDCLASSA wc{};
    wc.lpfnWndProc = &PreviewSink::windowProc;
    wc.hInstance = GetModuleHandleA(nullptr);
    wc.lpszClassName = "PhoneCamPreviewWindow";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassA(&wc);

    hwnd_ = CreateWindowExA(
      0,
      wc.lpszClassName,
      "PhoneCam Receiver Preview",
      WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      width,
      height,
      nullptr,
      nullptr,
      wc.hInstance,
      this
    );

    if (!hwnd_) {
      std::cerr << "Failed to create preview window.\n";
      return false;
    }

    return true;
  }

  bool send(const Frame& frame) override {
    frame_ = frame.bgr;
    width_ = frame.width;
    height_ = frame.height;
    InvalidateRect(hwnd_, nullptr, FALSE);
    pumpMessages();
    return !closed_;
  }

  void updateStatus(const ReceiverStatus& status) override {
    if (!hwnd_) return;
    std::ostringstream title;
    title << "PhoneCam Receiver - " << status.state;
    if (!status.target.empty()) {
      title << " - " << status.target;
    }
    if (status.width > 0 && status.height > 0) {
      title << " - " << status.width << "x" << status.height;
    }
    title << " - " << std::fixed << std::setprecision(1) << status.avgFps << " fps"
          << " - " << status.incomingMbps << " Mbps"
          << " - " << status.frames << " frames"
          << " - errors " << status.decodeErrors;
    SetWindowTextA(hwnd_, title.str().c_str());
  }

private:
  static LRESULT CALLBACK windowProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    PreviewSink* self = reinterpret_cast<PreviewSink*>(GetWindowLongPtrA(hwnd, GWLP_USERDATA));
    if (msg == WM_NCCREATE) {
      auto* creates = reinterpret_cast<CREATESTRUCTA*>(lp);
      self = reinterpret_cast<PreviewSink*>(creates->lpCreateParams);
      SetWindowLongPtrA(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcA(hwnd, msg, wp, lp);

    switch (msg) {
      case WM_CLOSE:
        self->closed_ = true;
        DestroyWindow(hwnd);
        return 0;
      case WM_DESTROY:
        self->closed_ = true;
        return 0;
      case WM_PAINT:
        self->paint(hwnd);
        return 0;
      default:
        return DefWindowProcA(hwnd, msg, wp, lp);
    }
  }

  void paint(HWND hwnd) {
    PAINTSTRUCT ps{};
    HDC hdc = BeginPaint(hwnd, &ps);
    if (!frame_.empty()) {
      BITMAPINFO bmi{};
      bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      bmi.bmiHeader.biWidth = width_;
      bmi.bmiHeader.biHeight = -height_;
      bmi.bmiHeader.biPlanes = 1;
      bmi.bmiHeader.biBitCount = 24;
      bmi.bmiHeader.biCompression = BI_RGB;

      RECT rect{};
      GetClientRect(hwnd, &rect);
      StretchDIBits(
        hdc,
        0,
        0,
        rect.right - rect.left,
        rect.bottom - rect.top,
        0,
        0,
        width_,
        height_,
        frame_.data(),
        &bmi,
        DIB_RGB_COLORS,
        SRCCOPY
      );
    }
    EndPaint(hwnd, &ps);
  }

  void pumpMessages() {
    MSG msg{};
    while (PeekMessageA(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageA(&msg);
    }
  }

  HWND hwnd_ = nullptr;
  int width_ = 0;
  int height_ = 0;
  bool closed_ = false;
  std::vector<uint8_t> frame_;
};
#elif defined(__APPLE__)
using PreviewSink = NullSink;
#else
using PreviewSink = NullSink;
#endif

#if PHONECAM_WITH_SOFTCAM
class SoftcamSink final : public FrameSink {
public:
  bool start(int width, int height, float fps) override {
    camera_ = scCreateCamera(width, height, fps);
    if (!camera_) {
      std::cerr << "Softcam failed to create PhoneCam Virtual Camera. Is softcam.dll registered?\n";
      return false;
    }
    std::cout << "Softcam virtual camera active. Select it from OBS/Zoom/Teams.\n";
    return true;
  }

  bool send(const Frame& frame) override {
    if (!camera_) return false;
    scSendFrame(camera_, frame.bgr.data());
    return true;
  }

  ~SoftcamSink() override {
    if (camera_) {
      scDeleteCamera(camera_);
      camera_ = nullptr;
    }
  }

private:
  scCamera camera_ = nullptr;
};
#endif

class CompositeSink final : public FrameSink {
public:
  void add(std::unique_ptr<FrameSink> sink) {
    sinks_.push_back(std::move(sink));
  }

  bool start(int width, int height, float fps) override {
    bool any = false;
    for (auto& sink : sinks_) {
      any = sink->start(width, height, fps) || any;
    }
    return any;
  }

  bool send(const Frame& frame) override {
    bool any = false;
    for (auto& sink : sinks_) {
      any = sink->send(frame) || any;
    }
    return any;
  }

  void updateStatus(const ReceiverStatus& status) override {
    for (auto& sink : sinks_) {
      sink->updateStatus(status);
    }
  }

private:
  std::vector<std::unique_ptr<FrameSink>> sinks_;
};

struct Options {
  std::string rtspUrl;
  float fps = 30.0f;
  bool fpsExplicit = false;
  int width = 1280;
  int height = 720;
  bool widthHeightExplicit = false;
  bool preview = true;
  bool softcam = true;
  bool selfTest = false;
  bool discover = false;
  bool autoDiscover = false;
  bool discoverySelfTest = false;
  bool pairCodeMismatchSelfTest = false;
  bool autoDiscoverySelectionSelfTest = false;
  bool autoDiscoverySelfTest = false;
  std::string autoDiscoverySelfTestUrl;
  std::string pairCode;
  int discoverSeconds = 5;
  int selfTestFrames = 120;
  int maxFrames = 0;
  bool fpsFromDiscovery = false;
  std::string snapshotPath;
};



struct RtspEndpoint {
  std::string host = "unknown";
  std::string port = "554";
  std::string path = "/";
};

int runReceiver(const Options& options);

std::string normalizePairCode(const std::string& input) {
  std::string digits;
  for (const unsigned char ch : input) {
    if (std::isdigit(ch)) {
      digits.push_back(static_cast<char>(ch));
    }
    if (digits.size() == 6) {
      break;
    }
  }
  return digits;
}

void printUsage() {
  std::cout << "Usage: phonecam-receiver\n"
            << "       phonecam-receiver --rtsp rtsp://PHONE_IP:8554/ [--fps 30] [--width 1280] [--height 720] [--frames 120] [--snapshot frame.ppm] [--no-preview] [--no-softcam]\n"
            << "       phonecam-receiver --auto-discover [--pair-code 123456] [--discover-seconds 5] [--fps 30] [--frames 120] [--snapshot frame.ppm] [--no-preview] [--no-softcam]\n"
            << "       phonecam-receiver --discover [--pair-code 123456] [--discover-seconds 5]\n"
            << "       phonecam-receiver --discovery-self-test [--pair-code 123456]\n"
            << "       phonecam-receiver --pair-code-mismatch-self-test\n"
            << "       phonecam-receiver --auto-discovery-selection-self-test\n"
            << "       phonecam-receiver --auto-discover-self-test rtsp://127.0.0.1:8554/path [--pair-code 123456] [--frames 60] [--snapshot frame.ppm] [--no-preview] [--no-softcam]\n"
            << "       phonecam-receiver --self-test [--fps 30] [--frames 120] [--snapshot frame.ppm] [--no-preview] [--no-softcam]\n\n"
            << "With no arguments, the receiver waits up to 15 seconds for a PhoneCam LAN discovery beacon.\n";
}

Options parseOptions(int argc, char** argv) {
  Options options;
  const bool noArguments = argc == 1;
  if (noArguments) {
    options.autoDiscover = true;
    options.discover = true;
    options.discoverSeconds = 15;
  }
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--rtsp" && i + 1 < argc) {
      options.rtspUrl = argv[++i];
    } else if (arg == "--fps" && i + 1 < argc) {
      options.fps = std::stof(argv[++i]);
      options.fpsExplicit = true;
    } else if (arg == "--no-preview") {
      options.preview = false;
    } else if (arg == "--no-softcam") {
      options.softcam = false;
    } else if (arg == "--self-test") {
      options.selfTest = true;
    } else if (arg == "--discover") {
      options.discover = true;
    } else if (arg == "--auto-discover") {
      options.autoDiscover = true;
      options.discover = true;
    } else if (arg == "--discovery-self-test") {
      options.discoverySelfTest = true;
      options.discover = true;
      options.discoverSeconds = 2;
    } else if (arg == "--pair-code-mismatch-self-test") {
      options.pairCodeMismatchSelfTest = true;
      options.discover = true;
      options.discoverSeconds = 2;
    } else if (arg == "--auto-discovery-selection-self-test") {
      options.autoDiscoverySelectionSelfTest = true;
      options.discover = true;
      options.autoDiscover = true;
      options.discoverSeconds = 2;
    } else if (arg == "--auto-discover-self-test" && i + 1 < argc) {
      options.autoDiscoverySelfTest = true;
      options.autoDiscoverySelfTestUrl = argv[++i];
      options.discover = true;
      options.autoDiscover = true;
      options.discoverSeconds = 2;
    } else if (arg == "--discover-seconds" && i + 1 < argc) {
      options.discoverSeconds = std::stoi(argv[++i]);
    } else if (arg == "--pair-code" && i + 1 < argc) {
      options.pairCode = argv[++i];
    } else if (arg == "--frames" && i + 1 < argc) {
      options.selfTestFrames = std::stoi(argv[++i]);
      options.maxFrames = options.selfTestFrames;
    } else if (arg == "--snapshot" && i + 1 < argc) {
      options.snapshotPath = argv[++i];
    } else if (arg == "--width" && i + 1 < argc) {
      options.width = std::stoi(argv[++i]);
      options.widthHeightExplicit = true;
    } else if (arg == "--height" && i + 1 < argc) {
      options.height = std::stoi(argv[++i]);
      options.widthHeightExplicit = true;
    } else if (arg == "--help" || arg == "-h") {
      printUsage();
      std::exit(0);
    } else {
      throw std::runtime_error("Unknown or incomplete option: " + arg);
    }
  }
  if (!options.selfTest && !options.discoverySelfTest && !options.pairCodeMismatchSelfTest &&
      !options.autoDiscoverySelectionSelfTest && !options.autoDiscoverySelfTest &&
      !options.discover && !options.autoDiscover && options.rtspUrl.empty()) {
    throw std::runtime_error("Missing --rtsp URL.");
  }
  if (options.autoDiscoverySelfTest && options.autoDiscoverySelfTestUrl.rfind("rtsp://", 0) != 0) {
    throw std::runtime_error("--auto-discover-self-test requires an RTSP URL.");
  }
  options.pairCode = normalizePairCode(options.pairCode);
  if (!options.pairCode.empty() && options.pairCode.size() != 6) {
    throw std::runtime_error("--pair-code must contain six digits.");
  }
  options.discoverSeconds = std::clamp(options.discoverSeconds, 1, 30);
  return options;
}

void configureSinks(CompositeSink& sink, const Options& options) {
  bool hasSink = false;
  if (options.preview) {
    sink.add(std::make_unique<PreviewSink>());
    hasSink = true;
  }
#if PHONECAM_WITH_SOFTCAM
  if (options.softcam) {
    sink.add(std::make_unique<SoftcamSink>());
    hasSink = true;
  }
#else
  if (options.softcam) {
    std::cout << "Softcam was not linked in this build; continuing without virtual camera output.\n";
  }
#endif
  if (!hasSink) {
    sink.add(std::make_unique<NullSink>());
  }
}

RtspEndpoint parseRtspEndpoint(const std::string& url) {
  RtspEndpoint endpoint;
  const auto scheme = url.find("://");
  std::string authorityAndPath = scheme == std::string::npos ? url : url.substr(scheme + 3);

  const auto slash = authorityAndPath.find('/');
  std::string authority = slash == std::string::npos ? authorityAndPath : authorityAndPath.substr(0, slash);
  endpoint.path = slash == std::string::npos ? "/" : authorityAndPath.substr(slash);

  if (!authority.empty() && authority.front() == '[') {
    const auto close = authority.find(']');
    if (close != std::string::npos) {
      endpoint.host = authority.substr(1, close - 1);
      if (close + 1 < authority.size() && authority[close + 1] == ':') {
        endpoint.port = authority.substr(close + 2);
      }
      return endpoint;
    }
  }

  const auto colon = authority.rfind(':');
  if (colon == std::string::npos) {
    endpoint.host = authority.empty() ? endpoint.host : authority;
  } else {
    endpoint.host = colon == 0 ? endpoint.host : authority.substr(0, colon);
    endpoint.port = colon + 1 < authority.size() ? authority.substr(colon + 1) : endpoint.port;
  }

  return endpoint;
}

void applyDiscoveredDevice(const phonecam::DiscoveryDevice& device, Options& options) {
  if (options.rtspUrl.empty()) {
    options.rtspUrl = device.url;
  }
  if (!options.fpsExplicit && device.fps > 0) {
    options.fps = static_cast<float>(device.fps);
    options.fpsFromDiscovery = true;
    std::cout << "Using discovered stream FPS: " << device.fps << "\n";
  }
  if (!options.widthHeightExplicit && device.width > 0 && device.height > 0) {
    options.width = device.width;
    options.height = device.height;
    std::cout << "Using discovered stream resolution: " << device.width << "x" << device.height << "\n";
  }
}

int runAutoDiscoverySelfTest(Options options) {
  const std::string advertisedPairCode = options.pairCode.empty() ? "123456" : options.pairCode;
  const std::string payload = "PHONECAM|1|" + options.autoDiscoverySelfTestUrl +
                              "|1280|720|60|2800000|Synthetic Android|" + advertisedPairCode;
  std::exception_ptr senderError;
  std::thread sender([payload, &senderError] {
    try {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
      phonecam::sendUdpPayload(payload, "127.0.0.1", kDiscoveryPort);
    } catch (...) {
      senderError = std::current_exception();
    }
  });

  std::vector<phonecam::DiscoveryDevice> devices;
  try {
    devices = phonecam::runDiscovery(options.discoverSeconds, options.pairCode);
  } catch (...) {
    if (sender.joinable()) {
      sender.join();
    }
    throw;
  }
  sender.join();
  if (senderError) {
    try {
      std::rethrow_exception(senderError);
    } catch (const std::exception& error) {
      std::cerr << "Auto-discovery self-test sender failed: " << error.what() << "\n";
    }
    return 2;
  }
  if (devices.empty()) {
    std::cerr << "Auto-discovery self-test failed: no synthetic beacon received.\n";
    return 2;
  }

  applyDiscoveredDevice(devices.front(), options);
  if (options.maxFrames == 0) {
    options.maxFrames = 60;
  }
  std::cout << "Auto-discovery self-test selected: " << options.rtspUrl << "\n";
  std::cout << "Opening " << options.rtspUrl << " via PhoneCam protocol" << std::endl;
  const auto endpoint = parseRtspEndpoint(options.rtspUrl);
  std::cout << "Receiver target: host=" << endpoint.host << ", port=" << endpoint.port
            << ", path=" << endpoint.path << std::endl;
  return runReceiver(options);
}

std::string avError(int code) {
  char buffer[AV_ERROR_MAX_STRING_SIZE]{};
  av_strerror(code, buffer, sizeof(buffer));
  return buffer;
}

std::string endpointLabel(const RtspEndpoint& endpoint) {
  return endpoint.host + ":" + endpoint.port + endpoint.path;
}

void writeSnapshotPpm(const Frame& frame, const std::string& path) {
  if (path.empty()) return;
  if (frame.width <= 0 || frame.height <= 0 || frame.bgr.empty()) {
    throw std::runtime_error("Cannot write snapshot because no decoded frame is available.");
  }

  std::ofstream out(path, std::ios::binary);
  if (!out) {
    throw std::runtime_error("Failed to open snapshot file for writing: " + path);
  }

  out << "P6\n" << frame.width << " " << frame.height << "\n255\n";
  for (size_t offset = 0; offset + 2 < frame.bgr.size(); offset += 3) {
    const char rgb[3] = {
      static_cast<char>(frame.bgr[offset + 2]),
      static_cast<char>(frame.bgr[offset + 1]),
      static_cast<char>(frame.bgr[offset + 0])
    };
    out.write(rgb, sizeof(rgb));
  }
  if (!out) {
    throw std::runtime_error("Failed to write snapshot file: " + path);
  }
}

int runReceiver(const Options& options) {
  const auto endpoint = parseRtspEndpoint(options.rtspUrl);
  const std::string targetLabel = endpointLabel(endpoint);

  const AVCodec* decoder = avcodec_find_decoder(AV_CODEC_ID_HEVC);
  if (!decoder) {
    std::cerr << "HEVC decoder not found\n";
    return 2;
  }
  AVCodecContext* codec = avcodec_alloc_context3(decoder);
  if (!codec) {
    std::cerr << "Failed to allocate codec context\n";
    return 2;
  }
  codec->flags |= AV_CODEC_FLAG_LOW_DELAY;
  int rc = avcodec_open2(codec, decoder, nullptr);
  if (rc < 0) {
    std::cerr << "Failed to open decoder: " << avError(rc) << "\n";
    avcodec_free_context(&codec);
    return 2;
  }

  struct DecodedFrame {
    int width = 0;
    int height = 0;
    std::vector<uint8_t> bgr;
  };

  std::mutex queueMutex;
  std::vector<DecodedFrame> frameQueue;
  std::atomic<bool> allSinksClosed{false};
  std::atomic<int64_t> decodeErrors{0};

  SwsContext* sws = nullptr;
  std::mutex decodeMutex;

  auto frameCallback = [&](const uint8_t* data, size_t len, uint32_t timestamp, bool) {
    if (allSinksClosed) return;

    AVPacket* packet = av_packet_alloc();
    packet->data = const_cast<uint8_t*>(data);
    packet->size = static_cast<int>(len);
    packet->pts = timestamp;

    {
      std::lock_guard<std::mutex> lock(decodeMutex);
      int rcSend = avcodec_send_packet(codec, packet);
      av_packet_free(&packet);
      if (rcSend < 0) {
        ++decodeErrors;
        return;
      }

      AVFrame* decoded = av_frame_alloc();
      while (avcodec_receive_frame(codec, decoded) == 0) {
        if (!sws || decoded->width != codec->width || decoded->height != codec->height) {
          sws_freeContext(sws);
          sws = sws_getContext(
            decoded->width,
            decoded->height,
            static_cast<AVPixelFormat>(decoded->format),
            decoded->width,
            decoded->height,
            AV_PIX_FMT_BGR24,
            SWS_FAST_BILINEAR,
            nullptr, nullptr, nullptr
          );
        }

        if (sws) {
          DecodedFrame df;
          df.width = decoded->width;
          df.height = decoded->height;
          df.bgr.resize(static_cast<size_t>(df.width) * static_cast<size_t>(df.height) * 3);
          uint8_t* dstData[4] = { df.bgr.data(), nullptr, nullptr, nullptr };
          int dstLinesize[4] = { df.width * 3, 0, 0, 0 };
          sws_scale(sws, decoded->data, decoded->linesize, 0, decoded->height, dstData, dstLinesize);

          {
            std::lock_guard<std::mutex> qLock(queueMutex);
            if (frameQueue.size() > 5) {
              frameQueue.erase(frameQueue.begin());
            }
            frameQueue.push_back(std::move(df));
          }
        }
      }
      av_frame_free(&decoded);
    }
  };

  phonecam::TransportMode transportMode = phonecam::TransportMode::UDP;
  if (options.rtspUrl.rfind("tcp://", 0) == 0) {
    transportMode = phonecam::TransportMode::TCP;
  }

  std::string host = endpoint.host;
  int controlPort = 47822;
  int mediaPort = 5004;

  if (!endpoint.port.empty()) {
    try {
      int parsedPort = std::stoi(endpoint.port);
      if (transportMode == phonecam::TransportMode::TCP) {
        controlPort = parsedPort;
      } else {
        mediaPort = parsedPort;
      }
    } catch (...) {}
  }

  phonecam::PhoneCamClient client(transportMode, host, controlPort, mediaPort);
  client.setFrameCallback(frameCallback);

  if (!client.start(options.width, options.height, static_cast<int>(options.fps))) {
    std::cerr << "Failed to start PhoneCamClient with target " << options.width << "x" << options.height << " @ " << static_cast<int>(options.fps) << " fps\n";
    {
      std::lock_guard<std::mutex> lock(decodeMutex);
      avcodec_free_context(&codec);
    }
    return 2;
  }

  CompositeSink sink;
  configureSinks(sink, options);
  bool sinkStarted = false;
  int64_t frames = 0;
  Frame snapshotFrame;
  auto started = std::chrono::steady_clock::now();
  auto lastLog = started;

  auto buildStatus = [&](const std::string& state, int width, int height) {
    const auto now = std::chrono::steady_clock::now();
    const double elapsed = std::chrono::duration<double>(now - started).count();
    auto clientStats = client.getStats();
    ReceiverStatus status;
    status.state = state;
    status.target = targetLabel;
    status.width = width;
    status.height = height;
    status.frames = frames;
    status.avgFps = elapsed > 0.0 ? frames / elapsed : 0.0;
    status.incomingMbps = clientStats.networkBytes * 8.0 / (elapsed > 0.0 ? elapsed : 1.0) / 1000000.0;
    status.decodeErrors = decodeErrors;
    return status;
  };

  while (!allSinksClosed) {
    DecodedFrame df;
    bool hasFrame = false;
    {
      std::lock_guard<std::mutex> qLock(queueMutex);
      if (!frameQueue.empty()) {
        df = std::move(frameQueue.front());
        frameQueue.erase(frameQueue.begin());
        hasFrame = true;
      }
    }

    if (hasFrame) {
      Frame frame;
      frame.width = df.width;
      frame.height = df.height;
      frame.bgr = std::move(df.bgr);

      if (!sinkStarted) {
        sinkStarted = sink.start(frame.width, frame.height, options.fps);
        sink.updateStatus(buildStatus("connected", frame.width, frame.height));
      }

      if (!sink.send(frame)) {
        std::cout << "All sinks closed.\n";
        allSinksClosed = true;
        break;
      }

      if (!options.snapshotPath.empty()) {
        snapshotFrame = frame;
      }

      client.reportDecodedFrame(0);
      ++frames;

      const auto now = std::chrono::steady_clock::now();
      if (now - lastLog > std::chrono::seconds(2)) {
        auto clientStats = client.getStats();
        std::cout << "Decoded " << frames << " frames, avg " << (frames / std::chrono::duration<double>(now - started).count())
                  << " fps, loss " << clientStats.lossPercent << "%, jitter " << clientStats.jitterMs << " ms\n";
        sink.updateStatus(buildStatus("connected", frame.width, frame.height));
        lastLog = now;
      }

      if (options.maxFrames > 0 && frames >= options.maxFrames) {
        break;
      }
    } else {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
  }

  client.stop();

  {
    std::lock_guard<std::mutex> lock(decodeMutex);
    if (sws) sws_freeContext(sws);
    avcodec_free_context(&codec);
  }

  const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
  if (elapsed > 0.0) {
    std::cout << "Receiver summary: " << frames << " frames, avg " << frames / elapsed
              << " fps, decode errors " << decodeErrors << "\n";
  }

  const bool hasEnoughFrames = options.maxFrames <= 0 || frames >= options.maxFrames;
  int exitCode = frames > 0 && hasEnoughFrames ? 0 : 2;

  if (!options.snapshotPath.empty() && frames > 0) {
    try {
      writeSnapshotPpm(snapshotFrame, options.snapshotPath);
      std::cout << "Snapshot written: " << options.snapshotPath << "\n";
    } catch (const std::exception& error) {
      std::cerr << error.what() << "\n";
      exitCode = 2;
    }
  }

  if (frames == 0) {
    std::cerr << "Receiver decoded no video frames.\n";
  } else if (!hasEnoughFrames) {
    std::cerr << "Receiver stopped before requested frame count: " << frames
              << "/" << options.maxFrames << " frames.\n";
  }

  return exitCode;
}

int runSelfTest(const Options& options) {
  constexpr int width = 320;
  constexpr int height = 240;
  CompositeSink sink;
  configureSinks(sink, options);

  if (!sink.start(width, height, options.fps)) {
    return 2;
  }

  const auto frameDelay = std::chrono::duration<double>(1.0 / options.fps);
  Frame snapshotFrame;
  for (int frameIndex = 0; frameIndex < options.selfTestFrames; ++frameIndex) {
    Frame frame;
    frame.width = width;
    frame.height = height;
    frame.bgr.resize(width * height * 3);

    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < width; ++x) {
        const int offset = (y * width + x) * 3;
        frame.bgr[offset + 0] = static_cast<uint8_t>((x + frameIndex * 3) % 256);
        frame.bgr[offset + 1] = static_cast<uint8_t>((y + frameIndex * 2) % 256);
        frame.bgr[offset + 2] = static_cast<uint8_t>((x + y + frameIndex * 4) % 256);
      }
    }

    if (!sink.send(frame)) {
      return 2;
    }
    if (!options.snapshotPath.empty()) {
      snapshotFrame = frame;
    }
    std::this_thread::sleep_for(frameDelay);
  }

  if (!options.snapshotPath.empty()) {
    try {
      writeSnapshotPpm(snapshotFrame, options.snapshotPath);
      std::cout << "Snapshot written: " << options.snapshotPath << "\n";
    } catch (const std::exception& error) {
      std::cerr << error.what() << "\n";
      return 2;
    }
  }

  std::cout << "Self-test sent " << options.selfTestFrames << " generated frames.\n";
  return 0;
}

} // namespace

int main(int argc, char** argv) {
  try {
    Options options = parseOptions(argc, argv);
    if (options.selfTest) {
      return runSelfTest(options);
    }
    if (options.discoverySelfTest) {
      return phonecam::runDiscoverySelfTest(options.pairCode);
    }
    if (options.pairCodeMismatchSelfTest) {
      return phonecam::runPairCodeMismatchSelfTest();
    }
    if (options.autoDiscoverySelectionSelfTest) {
      return phonecam::runAutoDiscoverySelectionSelfTest();
    }
    if (options.autoDiscoverySelfTest) {
      return runAutoDiscoverySelfTest(options);
    }
    if (options.discover) {
      const auto devices = phonecam::runDiscovery(options.discoverSeconds, options.pairCode);
      if (!options.autoDiscover) {
        return devices.empty() ? 2 : 0;
      }
      if (devices.empty()) {
        std::cerr << "No PhoneCam devices discovered. Start the Android camera server on the same LAN, "
                  << "or pass the shown URL with --rtsp rtsp://PHONE_IP:8554/.\n";
        return 2;
      }
      applyDiscoveredDevice(devices.front(), options);
      std::cout << "Auto-discovery selected: " << options.rtspUrl << "\n";
    }
    if (options.rtspUrl.empty()) {
      throw std::runtime_error("Missing --rtsp URL.");
    }
    std::cout << "Opening " << options.rtspUrl << " via PhoneCam protocol" << std::endl;
    const auto endpoint = parseRtspEndpoint(options.rtspUrl);
    std::cout << "Receiver target: host=" << endpoint.host << ", port=" << endpoint.port
              << ", path=" << endpoint.path << std::endl;
    return runReceiver(options);
  } catch (const std::exception& error) {
    std::cerr << error.what() << "\n";
    printUsage();
    return 1;
  }
}
