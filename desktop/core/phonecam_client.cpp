#include "phonecam_client.h"
#include "control_parser.h"
#include <iostream>
#include <sstream>
#include <cstring>
#include <chrono>
#include <algorithm>
#include <cerrno>
#if !defined(_WIN32)
#include <fcntl.h>
#include <netinet/tcp.h>
#endif

namespace phonecam {

#if defined(_WIN32)
static void close_sock(socket_t s) { ::closesocket(s); }
#else
static void close_sock(socket_t s) { ::close(s); }
#endif

static bool wouldBlock() {
#if defined(_WIN32)
    const int error = WSAGetLastError();
    return error == WSAEWOULDBLOCK || error == WSAEINPROGRESS;
#else
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINPROGRESS || errno == EINTR;
#endif
}
static bool configureTcp(socket_t socket) {
    int noDelay = 1;
    setsockopt(socket, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&noDelay), sizeof(noDelay));
#if defined(_WIN32)
    u_long nonblocking = 1;
    if (ioctlsocket(socket, FIONBIO, &nonblocking) != 0) return false;
#else
    const int flags = fcntl(socket, F_GETFL, 0);
    if (flags < 0 || fcntl(socket, F_SETFL, flags | O_NONBLOCK) != 0) return false;
#endif
    return true;
}
static bool connectBounded(socket_t socket, const sockaddr_in& address) {
    if (!configureTcp(socket)) return false;
    if (::connect(socket, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == 0) return true;
    if (!wouldBlock()) return false;
    fd_set writeSet, errorSet;
    FD_ZERO(&writeSet); FD_SET(socket, &writeSet);
    FD_ZERO(&errorSet); FD_SET(socket, &errorSet);
    timeval timeout{3, 0};
    if (select(static_cast<int>(socket + 1), nullptr, &writeSet, &errorSet, &timeout) <= 0) return false;
    int error = 0;
#if defined(_WIN32)
    int size = sizeof(error);
#else
    socklen_t size = sizeof(error);
#endif
    return getsockopt(socket, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &size) == 0 && error == 0;
}

// A bounded poll makes stop reliable even for an unconnected UDP socket.
static bool readable(socket_t socket) {
    fd_set set; FD_ZERO(&set); FD_SET(socket, &set);
    timeval timeout{0, 100000};
    return select(static_cast<int>(socket + 1), &set, nullptr, nullptr, &timeout) > 0;
}
static void shutdown_sock(socket_t socket) {
    if (socket == INVALID_SOCKET_VAL) return;
#if defined(_WIN32)
    ::shutdown(socket, SD_BOTH);
#else
    ::shutdown(socket, SHUT_RDWR);
#endif
}

PhoneCamClient::PhoneCamClient(TransportMode mode, const std::string& host, int controlPort, int mediaPort)
    : mode_(mode), host_(host), controlPort_(controlPort), mediaPort_(mediaPort),
      controlSocket_(INVALID_SOCKET_VAL), mediaSocket_(INVALID_SOCKET_VAL),
      playoutBuffer_(mode == TransportMode::TCP ? 0 : 10) {
    
    depacketizer_.setAccessUnitCallback([this](const uint8_t* data, size_t len, uint32_t timestamp, bool complete) {
        auto requestRecovery = [&] {
            const auto now = std::chrono::steady_clock::now();
            if (now - lastPliTime_ >= std::chrono::milliseconds(250)) {
                lastPliTime_ = now;
                sendJson(makePliMessage());
            }
        };
        bool keyFrame = false;
        for (size_t i = 0; i + 4 < len; ++i) {
            if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
                const auto type = (data[i+3] >> 1) & 63;
                if (type >= 16 && type <= 23) { keyFrame = true; break; }
            }
        }
        if (!complete) {
            playoutBuffer_.clear(); awaitingKeyFrame_ = true; requestRecovery(); return;
        }
        if (awaitingKeyFrame_ && !keyFrame) { requestRecovery(); return; }
        awaitingKeyFrame_ = false;
        if (!playoutBuffer_.push(std::vector<uint8_t>(data, data + len), timestamp, true)) {
            // Skipping compressed reference frames requires a new random-access frame.
            playoutBuffer_.clear(); awaitingKeyFrame_ = !keyFrame;
            if (keyFrame) playoutBuffer_.push(std::vector<uint8_t>(data, data + len), timestamp, true);
            requestRecovery();
        }
    });

    depacketizer_.setNackCallback([this](const std::vector<uint16_t>& seqs) {
        if (mode_ == TransportMode::UDP) {
            sendJson(makeNackMessage(seqs));
        }
    });

    lastStatsTime_ = std::chrono::steady_clock::now();
}

PhoneCamClient::~PhoneCamClient() {
    stop();
}

bool PhoneCamClient::start(int targetWidth, int targetHeight, int targetFps, socket_t connectedSocket) {
    stop();
    const bool automatic = targetWidth == 0 && targetHeight == 0 && targetFps == 0;
    if ((!automatic && (targetWidth <= 0 || targetWidth > 3840 || targetHeight <= 0 || targetHeight > 2160 ||
        targetFps <= 0 || targetFps > 240)) || controlPort_ <= 0 || controlPort_ > 65535 ||
        mediaPort_ <= 0 || mediaPort_ > 65535 || (connectedSocket != INVALID_SOCKET_VAL && mode_ != TransportMode::TCP)) {
        if (connectedSocket != INVALID_SOCKET_VAL) close_sock(connectedSocket);
        return false;
    }
    depacketizer_.reset();
    playoutBuffer_.clear();
    hasFirstTimestamp_ = false;
    awaitingKeyFrame_ = true;
    latency_.reset(); adaptiveDelayMs_ = 10;
    if (manualDelayMs_ < 0) playoutBuffer_.setTargetDelay(mode_ == TransportMode::TCP ? 0 : 10);
    {
        std::lock_guard<std::mutex> lock(statsMutex_);
        negotiatedFormat_ = {};
        totalPacketsReceived_ = totalBytesReceived_ = packetsLost_ = nackRecoveries_ = 0;
        framesReceivedInInterval_ = framesDecoded_ = frameAgeCount_ = 0;
        currentJitterMs_ = lastNetworkFps_ = lastDecodeFps_ = runningFrameAgeMsSum_ = 0;
        lastStatsTime_ = std::chrono::steady_clock::now();
    }
    lastPliTime_ = {};
    targetWidth_ = targetWidth;
    targetHeight_ = targetHeight;
    targetFps_ = targetFps;
    running_ = true;

#if defined(_WIN32)
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) { if (connectedSocket != INVALID_SOCKET_VAL) close_sock(connectedSocket); running_ = false; return false; }
    winsockStarted_ = true;
#endif

    if (connectedSocket != INVALID_SOCKET_VAL) controlSocket_ = connectedSocket;
    auto fail = [this] { stop(); return false; };
    in_addr address{};
    if (inet_pton(AF_INET, host_.c_str(), &address) != 1) return fail();
    if (mode_ == TransportMode::UDP) {
        controlSocket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (controlSocket_ == INVALID_SOCKET_VAL) return fail();

        sockaddr_in localCtrl{};
        localCtrl.sin_family = AF_INET;
        localCtrl.sin_addr.s_addr = htonl(INADDR_ANY);
        localCtrl.sin_port = htons(0);
        if (bind(controlSocket_, reinterpret_cast<sockaddr*>(&localCtrl), sizeof(localCtrl)) < 0) {
            return fail();
        }

        controlServerAddr_.sin_family = AF_INET;
        controlServerAddr_.sin_port = htons(controlPort_);
        inet_pton(AF_INET, host_.c_str(), &controlServerAddr_.sin_addr);

        mediaSocket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (mediaSocket_ == INVALID_SOCKET_VAL) return fail();

        int receiveBytes = 4 * 1024 * 1024;
        setsockopt(mediaSocket_, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char*>(&receiveBytes), sizeof(receiveBytes));

        sockaddr_in localMedia{};
        localMedia.sin_family = AF_INET;
        localMedia.sin_addr.s_addr = htonl(INADDR_ANY);
        localMedia.sin_port = htons(mediaPort_);
        if (bind(mediaSocket_, reinterpret_cast<sockaddr*>(&localMedia), sizeof(localMedia)) < 0) {
            return fail();
        }

        controlThread_ = std::thread(&PhoneCamClient::controlThreadFunc, this);
        mediaThread_ = std::thread(&PhoneCamClient::mediaThreadFunc, this);
        sendJson(makeConnectMessage(targetWidth_, targetHeight_, targetFps_, "udp", mediaPort_));
    } else {
        if (connectedSocket == INVALID_SOCKET_VAL) controlSocket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (controlSocket_ == INVALID_SOCKET_VAL) return fail();

        sockaddr_in serverAddr{};
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_port = htons(controlPort_);
        inet_pton(AF_INET, host_.c_str(), &serverAddr.sin_addr);

        if (connectedSocket != INVALID_SOCKET_VAL ? !configureTcp(controlSocket_) : !connectBounded(controlSocket_, serverAddr)) {
            return fail();
        }

        controlThread_ = std::thread(&PhoneCamClient::controlThreadFunc, this);
        sendJson(makeConnectMessage(targetWidth_, targetHeight_, targetFps_, "tcp", 0));
    }

    keepaliveThread_ = std::thread(&PhoneCamClient::keepaliveThreadFunc, this);
    playoutThread_ = std::thread(&PhoneCamClient::playoutThreadFunc, this);
    return true;
}

void PhoneCamClient::stop() {
    if (running_) sendJson(makeStopMessage());
    // Threads remain joinable after EOF sets running_=false. Always join them.
    running_ = false;
    shutdown_sock(controlSocket_);
    shutdown_sock(mediaSocket_);
    if (controlThread_.joinable()) controlThread_.join();
    if (mediaThread_.joinable()) mediaThread_.join();
    if (keepaliveThread_.joinable()) keepaliveThread_.join();
    if (playoutThread_.joinable()) playoutThread_.join();
    std::lock_guard<std::mutex> lock(sendMutex_);
    if (controlSocket_ != INVALID_SOCKET_VAL) close_sock(controlSocket_);
    if (mediaSocket_ != INVALID_SOCKET_VAL) close_sock(mediaSocket_);
    controlSocket_ = mediaSocket_ = INVALID_SOCKET_VAL;
    playoutBuffer_.clear();
#if defined(_WIN32)
    if (winsockStarted_) WSACleanup();
    winsockStarted_ = false;
#endif
}

void PhoneCamClient::sendJson(const std::string& json) {
    std::lock_guard<std::mutex> lock(sendMutex_);
    if (!running_ || controlSocket_ == INVALID_SOCKET_VAL || json.size() > 65535) return;
    if (mode_ == TransportMode::UDP) {
        sendto(controlSocket_, json.data(), static_cast<int>(json.size()), 0,
               reinterpret_cast<sockaddr*>(&controlServerAddr_), sizeof(controlServerAddr_));
        return;
    }
    // Serialize header and body as one record, handling partial writes.
    std::vector<uint8_t> record(6 + json.size());
    record[0] = 1;
    const uint32_t length = static_cast<uint32_t>(json.size());
    for (int i = 0; i < 4; ++i) record[2 + i] = (length >> (24 - i * 8)) & 255;
    std::copy(json.begin(), json.end(), record.begin() + 6);
#if defined(__APPLE__)
    int noSigpipe = 1;
    setsockopt(controlSocket_, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, sizeof(noSigpipe));
#endif
    size_t offset = 0;
    while (running_ && offset < record.size()) {
        fd_set writable; FD_ZERO(&writable); FD_SET(controlSocket_, &writable);
        timeval timeout{0, 200000};
        if (select(static_cast<int>(controlSocket_ + 1), nullptr, &writable, nullptr, &timeout) <= 0) {
            running_ = false;
            return;
        }
#ifdef MSG_NOSIGNAL
        constexpr int flags = MSG_NOSIGNAL;
#else
        constexpr int flags = 0;
#endif
        const int written = send(controlSocket_, reinterpret_cast<const char*>(record.data() + offset),
                                 static_cast<int>(record.size() - offset), flags);
        if (written < 0 && wouldBlock()) continue;
        if (written <= 0) { running_ = false; return; }
        offset += written;
    }
}

bool PhoneCamClient::receiveExact(uint8_t* data, size_t size) {
    size_t offset = 0;
    while (running_ && offset < size) {
        if (!readable(controlSocket_)) continue;
        const int bytes = recv(controlSocket_, reinterpret_cast<char*>(data + offset), static_cast<int>(size - offset), 0);
        if (bytes < 0 && wouldBlock()) continue;
        if (bytes <= 0) { running_ = false; return false; }
        offset += bytes;
    }
    return offset == size;
}

void PhoneCamClient::controlThreadFunc() {
    std::vector<uint8_t> buffer(65536);
    
    if (mode_ == TransportMode::UDP) {
        while (running_) {
            if (!readable(controlSocket_)) continue;
            sockaddr_in sender{};
#if defined(_WIN32)
            int senderLen = sizeof(sender);
#else
            socklen_t senderLen = sizeof(sender);
#endif
            int bytes = recvfrom(controlSocket_, reinterpret_cast<char*>(buffer.data()), static_cast<int>(buffer.size() - 1), 0,
                                 reinterpret_cast<sockaddr*>(&sender), &senderLen);
            if (bytes <= 0) break;
            if (sender.sin_addr.s_addr != controlServerAddr_.sin_addr.s_addr ||
                sender.sin_port != controlServerAddr_.sin_port) continue;
            buffer[bytes] = '\0';
            handleControlMessage(std::string(reinterpret_cast<char*>(buffer.data()), bytes));
        }
    } else {
        while (running_) {
            uint8_t header[6]{};
            if (!receiveExact(header, sizeof(header))) return;
            const uint8_t channel = header[0];
            const uint32_t length = (static_cast<uint32_t>(header[2]) << 24) |
                (static_cast<uint32_t>(header[3]) << 16) |
                (static_cast<uint32_t>(header[4]) << 8) | header[5];
            // Each media record is one RTP packet, never a whole raw frame.
            if (header[1] != 0 || (channel != 1 && channel != 2) || length == 0 || length > 65535) {
                running_ = false;
                return;
            }
            buffer.resize(length);
            if (!receiveExact(buffer.data(), length)) return;
            const auto& payload = buffer;

            if (channel == 0x01) {
                handleControlMessage(std::string(reinterpret_cast<const char*>(payload.data()), length));
            } else if (channel == 0x02) {
                {
                    std::lock_guard<std::mutex> lock(statsMutex_);
                    totalPacketsReceived_++;
                    totalBytesReceived_ += length + 6;
                }
                depacketizer_.feedPacket(payload.data(), payload.size());
            }
        }
    }
}

void PhoneCamClient::mediaThreadFunc() {
    std::vector<uint8_t> buffer(65536);
    while (running_) {
        if (!readable(mediaSocket_)) {
            depacketizer_.flushStaleAccessUnit();
            continue;
        }
        sockaddr_in sender{};
#if defined(_WIN32)
        int senderLen = sizeof(sender);
#else
        socklen_t senderLen = sizeof(sender);
#endif
        int bytes = recvfrom(mediaSocket_, reinterpret_cast<char*>(buffer.data()), static_cast<int>(buffer.size()), 0, reinterpret_cast<sockaddr*>(&sender), &senderLen);
        if (bytes <= 0) break;
        if (sender.sin_addr.s_addr != controlServerAddr_.sin_addr.s_addr) continue;
        
        {
            std::lock_guard<std::mutex> lock(statsMutex_);
            totalPacketsReceived_++;
            totalBytesReceived_ += bytes;
        }
        depacketizer_.feedPacket(buffer.data(), bytes);
    }
}

void PhoneCamClient::handleControlMessage(const std::string& json) {
    ControlMessage msg = parseControlMessage(json);
    if (msg.type == "connect_ack") {
        if (msg.status == "success" && msg.width > 0 && msg.width <= 3840 && msg.height > 0 && msg.height <= 2160 && msg.fps > 0 && msg.fps <= 240) {
            { std::lock_guard<std::mutex> lock(statsMutex_); negotiatedFormat_ = {msg.width, msg.height, msg.fps}; }
            sendJson(makeStartMessage());
        } else { running_ = false; }
    } else if (msg.type == "start_ack" && msg.status != "success") {
        running_ = false;
    }
}

void PhoneCamClient::keepaliveThreadFunc() {
    auto lastPing = std::chrono::steady_clock::now();
    auto lastFeedback = std::chrono::steady_clock::now();

    while (running_) {
        auto now = std::chrono::steady_clock::now();
        if (now - lastPing >= std::chrono::seconds(1)) {
            sendJson(makePingMessage());
            lastPing = now;
        }
        if (now - lastFeedback >= std::chrono::milliseconds(500)) {
            RtpHevcDepacketizer::Stats depStats = depacketizer_.statsSnapshotAndReset();
            {
                std::lock_guard<std::mutex> lock(statsMutex_);
                 packetsLost_ += depStats.packetsLost;
                 nackRecoveries_ += depStats.nackRecoveries;
                 currentJitterMs_ = depStats.jitter / 90.0;
            }
            double lossFraction = 0.0;
            if (depStats.packetsReceived + depStats.packetsLost > 0) {
                lossFraction = static_cast<double>(depStats.packetsLost) / (depStats.packetsReceived + depStats.packetsLost);
            }
            if (mode_ == TransportMode::UDP) {
                if (manualDelayMs_ < 0) {
                    adaptiveDelayMs_ = latency_.update(depStats.jitter / 90.0, lossFraction);
                    playoutBuffer_.setTargetDelay(adaptiveDelayMs_);
                }
                sendJson(makeFeedbackMessage(lossFraction, currentJitterMs_));
            }
            lastFeedback = now;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}

void PhoneCamClient::playoutThreadFunc() {
    PlayoutFrame frame;
    while (running_) {
        if (playoutBuffer_.pop(frame, std::chrono::milliseconds(100))) {
            {
                std::lock_guard<std::mutex> lock(statsMutex_);
                framesReceivedInInterval_++;
            }

            auto now = std::chrono::steady_clock::now();
            if (!hasFirstTimestamp_) {
                firstRtpTimestamp_ = frame.rtpTimestamp;
                lastRtpTimestamp_ = frame.rtpTimestamp;
                elapsedRtpTicks_ = 0;
                firstFrameTime_ = now;
                hasFirstTimestamp_ = true;
            }
            elapsedRtpTicks_ += static_cast<int32_t>(frame.rtpTimestamp - lastRtpTimestamp_);
            lastRtpTimestamp_ = frame.rtpTimestamp;
            double elapsedSec = elapsedRtpTicks_ / 90000.0;
            auto estimatedCaptureTime = firstFrameTime_ + std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(elapsedSec));
            double frameAgeMs = std::chrono::duration<double, std::milli>(now - estimatedCaptureTime).count();
            
            {
                std::lock_guard<std::mutex> lock(statsMutex_);
                runningFrameAgeMsSum_ += frameAgeMs;
                frameAgeCount_++;
            }

            if (frameCallback_) {
                frameCallback_(frame.data.data(), frame.data.size(), frame.rtpTimestamp, frame.complete);
            }
        }
    }
}

PhoneCamClient::NegotiatedFormat PhoneCamClient::negotiatedFormat() {
    std::lock_guard<std::mutex> lock(statsMutex_); return negotiatedFormat_;
}

void PhoneCamClient::reportDecodedFrame(uint32_t) {
    std::lock_guard<std::mutex> lock(statsMutex_);
    framesDecoded_++;
}

PhoneCamClient::ClientStats PhoneCamClient::getStats() {
    std::lock_guard<std::mutex> lock(statsMutex_);
    ClientStats stats;
    stats.networkPackets = totalPacketsReceived_;
    stats.networkBytes = totalBytesReceived_;
    uint64_t totalExpected = totalPacketsReceived_ + packetsLost_;
    stats.lossPercent = totalExpected > 0 ? (100.0 * packetsLost_) / totalExpected : 0.0;
    stats.nackRecoveries = nackRecoveries_;
    stats.jitterMs = currentJitterMs_;
    stats.playoutDelayMs = manualDelayMs_ >= 0 ? manualDelayMs_.load() : (mode_ == TransportMode::TCP ? 0 : adaptiveDelayMs_.load());

    auto now = std::chrono::steady_clock::now();
    double duration = std::chrono::duration<double>(now - lastStatsTime_).count();
    if (duration > 0.0) {
        lastNetworkFps_ = framesReceivedInInterval_ / duration;
        lastDecodeFps_ = framesDecoded_ / duration;
        framesReceivedInInterval_ = 0;
        framesDecoded_ = 0;
        lastStatsTime_ = now;
    }
    stats.networkFps = lastNetworkFps_;
    stats.decodeFps = lastDecodeFps_;

    if (frameAgeCount_ > 0) {
        stats.avgFrameAgeMs = runningFrameAgeMsSum_ / frameAgeCount_;
        runningFrameAgeMsSum_ = 0.0;
        frameAgeCount_ = 0;
    } else {
        stats.avgFrameAgeMs = 0.0;
    }
    return stats;
}

} // namespace phonecam
