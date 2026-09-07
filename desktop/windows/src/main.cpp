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
#include <condition_variable>
#include <cmath>
#include "video_decoder.h"

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
#include "receiver_connection.h"
#include "connection_panel.h"
#include <csignal>

volatile std::sig_atomic_t listenRunning = 1;

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
  ~PreviewSink() override { if (hwnd_) DestroyWindow(hwnd_); }
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
    const auto now = std::chrono::steady_clock::now();
    if (frame_.empty() || now - lastPaint_ >= std::chrono::milliseconds(33)) {
      frame_ = frame.bgr;
      width_ = frame.width;
      height_ = frame.height;
      InvalidateRect(hwnd_, nullptr, FALSE);
      lastPaint_ = now;
    }
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
        self->hwnd_ = nullptr;
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
  std::chrono::steady_clock::time_point lastPaint_{};
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
    if (camera_) scDeleteCamera(camera_);
    width_ = width; height_ = height;
    camera_ = scCreateCamera(width, height, fps);
    if (!camera_) {
      std::cerr << "Softcam failed to create PhoneCam Virtual Camera. Is softcam.dll registered?\n";
      return false;
    }
    std::cout << "Softcam virtual camera active. Select it from OBS/Zoom/Teams.\n";
    return true;
  }

  bool send(const Frame& frame) override {
    if (!camera_ || frame.width != width_ || frame.height != height_ ||
        frame.bgr.size() != static_cast<size_t>(width_) * height_ * 3) return false;
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
  int width_ = 0, height_ = 0;
};
#endif

class CompositeSink final : public FrameSink {
public:
  void add(std::unique_ptr<FrameSink> sink) {
    sinks_.push_back(std::move(sink));
  }

  bool start(int width, int height, float fps) override {
    for (auto& sink : sinks_) {
      if (!sink->start(width, height, fps)) return false;
    }
    return !sinks_.empty();
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
  bool hardwareDecode = true;
  bool inputFile = false;
  bool listen = false;
  int listenPort = phonecam::kReceiverPort;
  socket_t connectedSocket = INVALID_SOCKET_VAL;
  bool automaticFormat = false;
  int idleTimeoutSeconds = 15;
  int jitterMs = -1;
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
  std::string port;
  std::string path = "/";
};

int runReceiver(const Options& options);
int runRtspReceiver(const Options& options);

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
            << "       phonecam-receiver --rtsp udp://PHONE_IP:5004 --width 1920 --height 1080 --fps 240 [--jitter-ms 20] [--software-decode]\n"
            << "       phonecam-receiver --input FILE [--frames 60] [--no-preview] [--no-softcam]\n"
            << "       phonecam-receiver --dependency-info | --release-check\n"
            << "       phonecam-receiver --self-test [--fps 30] [--frames 120] [--snapshot frame.ppm] [--no-preview] [--no-softcam]\n\n"
            << "Native transport: --rtsp udp://PHONE_IP:5004/ or tcp://PHONE_IP:47822/; --software-decode disables D3D11VA; --idle-timeout SECONDS (default 15).\n"
            << "With no arguments (or --listen), open the connection window and wait for a phone. Use --auto-discover for legacy sender discovery.\n";
}

Options parseOptions(int argc, char** argv) {
  Options options;
  const bool noArguments = argc == 1;
  if (noArguments) {
    options.listen = true;
  }
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--rtsp" && i + 1 < argc) {
      options.rtspUrl = argv[++i];
    } else if (arg == "--listen") {
      options.listen = true;
    } else if (arg == "--listen-port" && i + 1 < argc) {
      options.listen = true; options.listenPort = std::stoi(argv[++i]);
    } else if (arg == "--input" && i + 1 < argc) {
      options.rtspUrl = argv[++i];
      options.inputFile = true;
    } else if (arg == "--fps" && i + 1 < argc) {
      options.fps = std::stof(argv[++i]);
      options.fpsExplicit = true;
    } else if (arg == "--jitter-ms" && i + 1 < argc) {
      options.jitterMs = std::stoi(argv[++i]);
    } else if (arg == "--software-decode") {
      options.hardwareDecode = false;
    } else if (arg == "--idle-timeout" && i + 1 < argc) {
      options.idleTimeoutSeconds = std::stoi(argv[++i]);
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
      !options.listen && !options.discover && !options.autoDiscover && options.rtspUrl.empty()) {
    throw std::runtime_error("Missing --rtsp URL.");
  }
  if (options.autoDiscoverySelfTest && options.autoDiscoverySelfTestUrl.rfind("rtsp://", 0) != 0) {
    throw std::runtime_error("--auto-discover-self-test requires an RTSP URL.");
  }
  if (!std::isfinite(options.fps) || options.fps < 1 || options.fps > 240 ||
      options.width < 4 || options.width > 3840 || options.width % 4 != 0 ||
      options.height < 2 || options.height > 2160 || options.height % 2 != 0 ||
      options.selfTestFrames <= 0 || options.jitterMs < -1 || options.jitterMs > 1000 || options.idleTimeoutSeconds < 1 || options.idleTimeoutSeconds > 300)
    throw std::runtime_error("Invalid dimensions, FPS (1..240), frame count or idle timeout (1..300).");
  if (options.listenPort < 1 || options.listenPort > 65535) throw std::runtime_error("Invalid listen port");
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
  if (!options.fpsExplicit && device.fps > 0 && device.fps <= 240) {
    options.fps = static_cast<float>(device.fps);
    options.fpsFromDiscovery = true;
    std::cout << "Using discovered stream FPS: " << device.fps << "\n";
  }
  if (!options.widthHeightExplicit && device.width > 0 && device.width <= 3840 && device.width % 4 == 0 && device.height > 0 && device.height <= 2160 && device.height % 2 == 0) {
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
  std::vector<uint8_t> row(static_cast<size_t>(frame.width) * 3);
  for (int y = 0; y < frame.height; ++y) {
    const auto* source = frame.bgr.data() + y * row.size();
    for (size_t x = 0; x < row.size(); x += 3) {
      row[x] = source[x + 2]; row[x + 1] = source[x + 1]; row[x + 2] = source[x];
    }
    out.write(reinterpret_cast<const char*>(row.data()), static_cast<std::streamsize>(row.size()));
  }
  if (!out) {
    throw std::runtime_error("Failed to write snapshot file: " + path);
  }
}

int runReceiver(const Options& inputOptions) {
  Options options = inputOptions;
  struct AcceptedSocket {
    socket_t value;
    ~AcceptedSocket() {
      if (value == INVALID_SOCKET_VAL) return;
#if defined(_WIN32)
      closesocket(value);
#else
      close(value);
#endif
    }
  } accepted{options.connectedSocket};
  if (options.inputFile || options.rtspUrl.rfind("rtsp://", 0) == 0 || options.rtspUrl.rfind("rtsps://", 0) == 0)
    return runRtspReceiver(options);
  if (options.rtspUrl.rfind("udp://", 0) != 0 && options.rtspUrl.rfind("tcp://", 0) != 0)
    throw std::runtime_error("Use udp://, tcp://, rtsp:// or --input FILE.");
  if (!options.widthHeightExplicit && !options.fpsFromDiscovery) { options.width = 3840; options.height = 2160; }
  if (!options.fpsExplicit && !options.fpsFromDiscovery) options.fps = 60;
  const auto endpoint = parseRtspEndpoint(options.rtspUrl);
  const std::string targetLabel = endpointLabel(endpoint);

  VideoDecoder decoder(options.hardwareDecode);
  std::cout << "HEVC decode: " << (decoder.hardwareEnabled() ? "D3D11VA" : "software") << "\n";
  std::mutex queueMutex;
  std::condition_variable frameReady;
  Frame pendingFrame, producerFrame;
  bool pending = false;
  std::atomic<bool> allSinksClosed{false};
  std::atomic<int64_t> decodeErrors{0};
  std::atomic<int64_t> framesReplaced{0};
  std::atomic<int64_t> resolutionChanges{0};
  int outputWidth = options.automaticFormat ? 0 : options.width;
  int outputHeight = options.automaticFormat ? 0 : options.height;

  auto frameCallback = [&](const uint8_t* data, size_t len, uint32_t timestamp, bool complete) {
    if (allSinksClosed || !complete) return;
    try {
      decodeErrors += decoder.decode(data, len, timestamp, [&](AVFrame* decoded) {
        if (outputWidth == 0) { outputWidth = decoded->width; outputHeight = decoded->height; }
        if (decoded->width != outputWidth || decoded->height != outputHeight) ++resolutionChanges;
        // Keep the virtual camera format fixed across sender ABR resolution changes.
        producerFrame.width = outputWidth;
        producerFrame.height = outputHeight;
        producerFrame.bgr.resize(static_cast<size_t>(outputWidth) * outputHeight * 3);
        if (!decoder.convert(decoded, outputWidth, outputHeight, producerFrame.bgr.data())) {
          ++decodeErrors;
          return;
        }
        {
          std::lock_guard<std::mutex> lock(queueMutex);
          if (pending) ++framesReplaced;
          std::swap(pendingFrame, producerFrame);
          pending = true;
        }
        frameReady.notify_one();
      });
    } catch (const std::exception& error) {
      std::cerr << "Decoder stopped: " << error.what() << "\n";
      ++decodeErrors;
      allSinksClosed = true;
      frameReady.notify_one();
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
  if (options.jitterMs >= 0) client.setPlayoutDelayMs(options.jitterMs);

  accepted.value = INVALID_SOCKET_VAL; // start takes ownership, including failure paths.
  if (!client.start(options.automaticFormat ? 0 : options.width, options.automaticFormat ? 0 : options.height,
                    options.automaticFormat ? 0 : static_cast<int>(options.fps), options.connectedSocket)) {
    std::cerr << "Failed to start PhoneCamClient with target " << options.width << "x" << options.height << " @ " << static_cast<int>(options.fps) << " fps\n";
    client.stop();
    return 2;
  }

  CompositeSink sink;
  configureSinks(sink, options);
  bool sinkStarted = false;
  int64_t frames = 0;
  Frame snapshotFrame;
  auto started = std::chrono::steady_clock::now();
  auto lastLog = started;
  auto lastFrameTime = started;
  Frame frame;

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

  bool userClosed = false;
  while (!allSinksClosed && (!options.listen || listenRunning)) {
    bool hasFrame = false;
    {
      std::unique_lock<std::mutex> lock(queueMutex);
      frameReady.wait_for(lock, std::chrono::milliseconds(100), [&] { return pending || allSinksClosed.load(); });
      if (pending) {
        std::swap(frame, pendingFrame);
        pending = false;
        hasFrame = true;
      }
    }
    if (!client.isRunning() || std::chrono::steady_clock::now() - lastFrameTime > std::chrono::seconds(options.idleTimeoutSeconds)) {
      std::cerr << "Stream disconnected or timed out.\n";
      break;
    }
    if (hasFrame) {
      lastFrameTime = std::chrono::steady_clock::now();
      if (!sinkStarted) {
        const auto negotiated = client.negotiatedFormat();
        std::cout << "Negotiated source: " << negotiated.width << "x" << negotiated.height << " @ " << negotiated.fps << " fps\n";
        const float fps = negotiated.fps > 0 ? static_cast<float>(negotiated.fps) : options.fps;
        sinkStarted = sink.start(frame.width, frame.height, fps);
        if (!sinkStarted) break;
        sink.updateStatus(buildStatus("connected", frame.width, frame.height));
      }

      if (!sink.send(frame)) {
        userClosed = true;
        std::cout << "All sinks closed.\n";
        allSinksClosed = true;
        break;
      }

      if (!options.snapshotPath.empty() && snapshotFrame.bgr.empty()) {
        snapshotFrame = frame;
      }

      client.reportDecodedFrame(0);
      ++frames;

      const auto now = std::chrono::steady_clock::now();
      if (now - lastLog > std::chrono::seconds(2)) {
        auto clientStats = client.getStats();
        std::cout << "Decoded " << frames << " frames, avg " << (frames / std::chrono::duration<double>(now - started).count())
                  << " fps, loss " << clientStats.lossPercent << "%, jitter " << clientStats.jitterMs << " ms, playout " << clientStats.playoutDelayMs << " ms\n";
        sink.updateStatus(buildStatus("connected", frame.width, frame.height));
        lastLog = now;
      }

      if (options.maxFrames > 0 && frames >= options.maxFrames) {
        break;
      }
    }
  }

  client.stop();
  std::cout << "Frames replaced by newer output: " << framesReplaced << "\n";
  std::cout << "Frames with different source resolution: " << resolutionChanges << "\n";

  const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
  if (elapsed > 0.0) {
    std::cout << "Receiver summary: " << frames << " frames, avg " << frames / elapsed
              << " fps, decode errors " << decodeErrors << "\n";
  }

  const bool hasEnoughFrames = options.maxFrames <= 0 || frames >= options.maxFrames;
  int exitCode = frames > 0 && hasEnoughFrames && decodeErrors == 0 ? 0 : 2;

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

  return userClosed && options.listen ? 3 : exitCode;
}

// Standard RTSP remains a real demux/decode path; it is not PhoneCam UDP.
int runRtspReceiver(const Options& options) {
  struct Input {
    AVFormatContext* format = avformat_alloc_context();
    AVPacket* packet = av_packet_alloc();
    std::chrono::steady_clock::time_point deadline;
    ~Input() { av_packet_free(&packet); avformat_close_input(&format); }
  } input;
  if (!input.format || !input.packet) throw std::bad_alloc();
  auto refreshDeadline = [&] {
    input.deadline = std::chrono::steady_clock::now() + std::chrono::seconds(options.idleTimeoutSeconds);
  };
  refreshDeadline();
  input.format->interrupt_callback = {
    [](void* opaque) -> int {
      return std::chrono::steady_clock::now() > static_cast<Input*>(opaque)->deadline;
    }, &input
  };
  AVDictionary* settings = nullptr;
  av_dict_set(&settings, "rtsp_transport", "tcp", 0);
  av_dict_set(&settings, "rw_timeout", "5000000", 0);
  int rc = avformat_open_input(&input.format, options.rtspUrl.c_str(), nullptr, &settings);
  av_dict_free(&settings);
  if (rc < 0) throw std::runtime_error("Cannot open stream: " + avError(rc));
  rc = avformat_find_stream_info(input.format, nullptr);
  if (rc < 0) throw std::runtime_error("Cannot read video format: " + avError(rc));
  int video = av_find_best_stream(input.format, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
  if (video < 0) throw std::runtime_error("No video stream");
  AVStream* stream = input.format->streams[video];
  Options output = options;
  if (!options.widthHeightExplicit && !options.fpsFromDiscovery) {
    output.width = stream->codecpar->width;
    output.height = stream->codecpar->height;
  }
  if (!options.fpsExplicit && !options.fpsFromDiscovery) {
    AVRational rate = av_guess_frame_rate(input.format, stream, nullptr);
    if (rate.num > 0 && rate.den > 0) output.fps = static_cast<float>(av_q2d(rate));
  }
  if (output.width < 4 || output.width > 3840 || output.width % 4 != 0 ||
      output.height < 2 || output.height > 2160 || output.height % 2 != 0 ||
      !std::isfinite(output.fps) || output.fps < 1 || output.fps > 240)
    throw std::runtime_error("Unsupported output size/rate; use --width/--height/--fps.");
  VideoDecoder decoder(options.hardwareDecode, stream->codecpar->codec_id, stream->codecpar);
  CompositeSink sink;
  configureSinks(sink, output);
  if (!sink.start(output.width, output.height, output.fps)) return 2;
  Frame frame, snapshot;
  frame.width = output.width; frame.height = output.height;
  frame.bgr.resize(static_cast<size_t>(frame.width) * frame.height * 3);
  int64_t frames = 0, decodeErrors = 0;
  uint64_t bytes = 0;
  bool closed = false;
  const auto started = std::chrono::steady_clock::now();
  auto lastLog = started;
  auto deliver = [&](AVFrame* decoded) {
        if (closed || (options.maxFrames > 0 && frames >= options.maxFrames)) return;
        if (!decoder.convert(decoded, frame.width, frame.height, frame.bgr.data())) { ++decodeErrors; return; }
        if (!sink.send(frame)) { closed = true; return; }
        ++frames;
        if (!options.snapshotPath.empty() && snapshot.bgr.empty()) snapshot = frame;
      };
  while (!closed && (options.maxFrames <= 0 || frames < options.maxFrames)) {
    refreshDeadline();
    rc = av_read_frame(input.format, input.packet);
    if (rc < 0) break;
    if (input.packet->stream_index == video) {
      bytes += input.packet->size;
      decodeErrors += decoder.decode(input.packet->data, input.packet->size, 0, deliver);
    }
    av_packet_unref(input.packet);
    auto now = std::chrono::steady_clock::now();
    if (now - lastLog >= std::chrono::seconds(2)) {
      const double elapsed = std::chrono::duration<double>(now - started).count();
      ReceiverStatus status;
      status.state = "connected"; status.width = frame.width; status.height = frame.height;
      status.frames = frames; status.avgFps = frames / elapsed;
      status.incomingMbps = bytes * 8.0 / elapsed / 1000000.0;
      status.decodeErrors = decodeErrors;
      sink.updateStatus(status);
      lastLog = now;
    }
  }
  if (rc == AVERROR_EOF) decodeErrors += decoder.flush(deliver);
  if (!options.snapshotPath.empty() && !snapshot.bgr.empty()) writeSnapshotPpm(snapshot, options.snapshotPath);
  const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
  std::cout << "Receiver summary: " << frames << " frames, avg " << frames / elapsed
            << " fps, incoming " << bytes * 8.0 / elapsed / 1000000.0
            << " Mbps, decode errors " << decodeErrors << "\n";
  return frames > 0 && decodeErrors == 0 && (options.maxFrames <= 0 || frames >= options.maxFrames) ? 0 : 2;
}

int runSelfTest(const Options& options) {
  const int width = options.widthHeightExplicit ? options.width : 320;
  const int height = options.widthHeightExplicit ? options.height : 240;
  CompositeSink sink;
  configureSinks(sink, options);

  if (!sink.start(width, height, options.fps)) {
    return 2;
  }

  const auto frameDelay = std::chrono::duration<double>(1.0 / options.fps);
  Frame snapshotFrame;
  auto nextFrame = std::chrono::steady_clock::now();
  Frame frame;
  for (int frameIndex = 0; frameIndex < options.selfTestFrames; ++frameIndex) {
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
    nextFrame += std::chrono::duration_cast<std::chrono::steady_clock::duration>(frameDelay);
    std::this_thread::sleep_until(nextFrame);
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


int runListenReceiver(Options options) {
  std::signal(SIGINT, [](int) { listenRunning = 0; });
  phonecam::ReceiverListener listener(options.listenPort);
  const auto name = phonecam::computerName();
  phonecam::ReceiverAdvertisement advertisement(name, listener.port());
  ConnectionPanel panel(name, phonecam::localIPv4Addresses(), listener.port());
  options.automaticFormat = !options.widthHeightExplicit && !options.fpsExplicit;
  while (listenRunning && panel.pump()) {
    std::string peer;
    auto socket = listener.acceptPhone(peer, std::chrono::milliseconds(50));
    if (socket == INVALID_SOCKET_VAL) continue;
    options.connectedSocket = socket;
    options.rtspUrl = "tcp://" + peer + ":" + std::to_string(listener.port());
    panel.status("Phone connected. Starting camera…");
    panel.show(false);
    const int result = runReceiver(options);
    if (result == 3) return 0;
    if (options.maxFrames > 0) return result;
    panel.show(true);
    panel.status("Phone disconnected. Ready to reconnect — keep the phone app open.");
  }
  return 0;
}

int printDependencyInfo(bool checkRelease) {
  struct Library { const char* name; const char* license; const char* configuration; };
  const Library libraries[] = {
    {"avcodec", avcodec_license(), avcodec_configuration()},
    {"avformat", avformat_license(), avformat_configuration()},
    {"avutil", avutil_license(), avutil_configuration()},
    {"swscale", swscale_license(), swscale_configuration()}
  };
  bool allowed = true;
  for (const auto& library : libraries) {
    std::cout << library.name << ": " << library.license << "\n" << library.configuration << "\n";
    const std::string license = library.license, configuration = library.configuration;
    allowed = allowed && license.rfind("LGPL", 0) == 0 &&
        configuration.find("--enable-gpl") == std::string::npos &&
        configuration.find("--enable-nonfree") == std::string::npos &&
        configuration.find("--enable-shared") != std::string::npos;
  }
  if (checkRelease && !allowed) {
    std::cerr << "Release blocked: use shared LGPL FFmpeg libraries without GPL/nonfree components.\n";
    return 2;
  }
  return 0;
}

int main(int argc, char** argv) {
  if (argc == 2 && (std::string(argv[1]) == "--dependency-info" || std::string(argv[1]) == "--release-check"))
    return printDependencyInfo(std::string(argv[1]) == "--release-check");
  try {
    Options options = parseOptions(argc, argv);
    if (options.listen) return runListenReceiver(options);
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
