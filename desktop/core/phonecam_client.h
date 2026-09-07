#pragma once
#include "rtp_hevc.h"
#include "playout_buffer.h"
#include "latency_controller.h"
#include <string>
#include <vector>
#include <atomic>
#include <thread>
#include <mutex>
#include <functional>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
using socket_t = SOCKET;
#define INVALID_SOCKET_VAL INVALID_SOCKET
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
using socket_t = int;
#define INVALID_SOCKET_VAL -1
#endif

namespace phonecam {

enum class TransportMode {
    UDP,
    TCP
};

class PhoneCamClient {
public:
    PhoneCamClient(TransportMode mode, const std::string& host, int controlPort = 47822, int mediaPort = 5004);
    ~PhoneCamClient();

    bool start(int targetWidth = 1280, int targetHeight = 720, int targetFps = 30, socket_t connectedSocket = INVALID_SOCKET_VAL);
    void stop();
    void setPlayoutDelayMs(int milliseconds) { manualDelayMs_ = milliseconds; playoutBuffer_.setTargetDelay(milliseconds); }
    bool isRunning() const { return running_.load(); }

    using FrameCallback = std::function<void(const uint8_t* data, size_t len, uint32_t timestamp, bool complete)>;
    void setFrameCallback(FrameCallback cb) { frameCallback_ = cb; }

    struct ClientStats {
        uint64_t networkPackets = 0;
        uint64_t networkBytes = 0;
        double lossPercent = 0.0;
        uint64_t nackRecoveries = 0;
        double jitterMs = 0.0;
        int playoutDelayMs = 0;
        double networkFps = 0.0;
        double decodeFps = 0.0;
        double avgFrameAgeMs = 0.0;
    };
    ClientStats getStats();
    struct NegotiatedFormat { int width = 0, height = 0, fps = 0; };
    NegotiatedFormat negotiatedFormat();

    void reportDecodedFrame(uint32_t rtpTimestamp);

private:
    void controlThreadFunc();
    void mediaThreadFunc();
    void keepaliveThreadFunc();
    void playoutThreadFunc();

    bool receiveExact(uint8_t* data, size_t size);
    void sendJson(const std::string& json);
    void handleControlMessage(const std::string& json);

    TransportMode mode_;
    std::string host_;
    int controlPort_;
    int mediaPort_;

    std::atomic<bool> running_{false};
    std::mutex sendMutex_;
    bool winsockStarted_ = false;
    bool awaitingKeyFrame_ = true;
    std::atomic<int> manualDelayMs_{-1};
    LatencyController latency_;
    std::atomic<int> adaptiveDelayMs_{10};
    socket_t controlSocket_;
    socket_t mediaSocket_;

    std::thread controlThread_;
    std::thread mediaThread_;
    std::thread keepaliveThread_;
    std::thread playoutThread_;

    RtpHevcDepacketizer depacketizer_;
    PlayoutBuffer playoutBuffer_;
    FrameCallback frameCallback_;

    sockaddr_in controlServerAddr_{};
    std::chrono::steady_clock::time_point lastPliTime_{};

    // Stats
    std::mutex statsMutex_;
    NegotiatedFormat negotiatedFormat_;
    uint64_t totalPacketsReceived_ = 0;
    uint64_t totalBytesReceived_ = 0;
    uint64_t packetsLost_ = 0;
    uint64_t nackRecoveries_ = 0;
    double currentJitterMs_ = 0.0;

    uint64_t framesReceivedInInterval_ = 0;
    uint64_t framesDecoded_ = 0;
    double lastNetworkFps_ = 0.0;
    double lastDecodeFps_ = 0.0;
    double runningFrameAgeMsSum_ = 0.0;
    uint64_t frameAgeCount_ = 0;

    std::chrono::steady_clock::time_point lastStatsTime_;

    bool hasFirstTimestamp_ = false;
    uint32_t firstRtpTimestamp_ = 0;
    uint32_t lastRtpTimestamp_ = 0;
    int64_t elapsedRtpTicks_ = 0;
    std::chrono::steady_clock::time_point firstFrameTime_;

    int targetWidth_ = 1280;
    int targetHeight_ = 720;
    int targetFps_ = 30;
};

} // namespace phonecam
