#include "phonecam_client.h"
#include "control_parser.h"
#include <iostream>
#include <sstream>
#include <cstring>
#include <chrono>

namespace phonecam {

#if defined(_WIN32)
static void close_sock(socket_t s) { ::closesocket(s); }
#else
static void close_sock(socket_t s) { ::close(s); }
#endif

PhoneCamClient::PhoneCamClient(TransportMode mode, const std::string& host, int controlPort, int mediaPort)
    : mode_(mode), host_(host), controlPort_(controlPort), mediaPort_(mediaPort),
      controlSocket_(INVALID_SOCKET_VAL), mediaSocket_(INVALID_SOCKET_VAL),
      playoutBuffer_(mode == TransportMode::TCP ? 0 : 50) {
    
    depacketizer_.setAccessUnitCallback([this](const uint8_t* data, size_t len, uint32_t timestamp, bool complete) {
        playoutBuffer_.push(std::vector<uint8_t>(data, data + len), timestamp, complete);
        if (!complete && mode_ == TransportMode::UDP) {
            sendJson(makePliMessage());
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

bool PhoneCamClient::start(int targetWidth, int targetHeight, int targetFps) {
    targetWidth_ = targetWidth;
    targetHeight_ = targetHeight;
    targetFps_ = targetFps;
    running_ = true;

#if defined(_WIN32)
    WSADATA wsaData;
    WSAStartup(MAKEWORD(2, 2), &wsaData);
#endif

    if (mode_ == TransportMode::UDP) {
        controlSocket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (controlSocket_ == INVALID_SOCKET_VAL) return false;

        sockaddr_in localCtrl{};
        localCtrl.sin_family = AF_INET;
        localCtrl.sin_addr.s_addr = htonl(INADDR_ANY);
        localCtrl.sin_port = htons(0);
        if (bind(controlSocket_, reinterpret_cast<sockaddr*>(&localCtrl), sizeof(localCtrl)) < 0) {
            return false;
        }

        controlServerAddr_.sin_family = AF_INET;
        controlServerAddr_.sin_port = htons(controlPort_);
        inet_pton(AF_INET, host_.c_str(), &controlServerAddr_.sin_addr);

        mediaSocket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (mediaSocket_ == INVALID_SOCKET_VAL) return false;

        int reuse = 1;
        setsockopt(mediaSocket_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse), sizeof(reuse));

        sockaddr_in localMedia{};
        localMedia.sin_family = AF_INET;
        localMedia.sin_addr.s_addr = htonl(INADDR_ANY);
        localMedia.sin_port = htons(mediaPort_);
        if (bind(mediaSocket_, reinterpret_cast<sockaddr*>(&localMedia), sizeof(localMedia)) < 0) {
            return false;
        }

        controlThread_ = std::thread(&PhoneCamClient::controlThreadFunc, this);
        mediaThread_ = std::thread(&PhoneCamClient::mediaThreadFunc, this);
        sendJson(makeConnectMessage(targetWidth_, targetHeight_, targetFps_, "udp", mediaPort_));
    } else {
        controlSocket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (controlSocket_ == INVALID_SOCKET_VAL) return false;

        sockaddr_in serverAddr{};
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_port = htons(controlPort_);
        inet_pton(AF_INET, host_.c_str(), &serverAddr.sin_addr);

        if (connect(controlSocket_, reinterpret_cast<sockaddr*>(&serverAddr), sizeof(serverAddr)) < 0) {
            return false;
        }

        controlThread_ = std::thread(&PhoneCamClient::controlThreadFunc, this);
        sendJson(makeConnectMessage(targetWidth_, targetHeight_, targetFps_, "tcp", 0));
    }

    keepaliveThread_ = std::thread(&PhoneCamClient::keepaliveThreadFunc, this);
    playoutThread_ = std::thread(&PhoneCamClient::playoutThreadFunc, this);
    return true;
}

void PhoneCamClient::stop() {
    if (!running_) return;
    sendJson(makeStopMessage());
    running_ = false;

    if (controlSocket_ != INVALID_SOCKET_VAL) {
        close_sock(controlSocket_);
        controlSocket_ = INVALID_SOCKET_VAL;
    }
    if (mediaSocket_ != INVALID_SOCKET_VAL) {
        close_sock(mediaSocket_);
        mediaSocket_ = INVALID_SOCKET_VAL;
    }

    if (controlThread_.joinable()) controlThread_.join();
    if (mediaThread_.joinable()) mediaThread_.join();
    if (keepaliveThread_.joinable()) keepaliveThread_.join();
    if (playoutThread_.joinable()) playoutThread_.join();

#if defined(_WIN32)
    WSACleanup();
#endif
}

void PhoneCamClient::sendJson(const std::string& json) {
    if (controlSocket_ == INVALID_SOCKET_VAL) return;

    if (mode_ == TransportMode::UDP) {
        sendto(controlSocket_, json.data(), static_cast<int>(json.size()), 0,
               reinterpret_cast<sockaddr*>(&controlServerAddr_), sizeof(controlServerAddr_));
    } else {
        uint8_t header[6];
        header[0] = 0x01;
        header[1] = 0x00;
        uint32_t len = static_cast<uint32_t>(json.size());
        header[2] = (len >> 24) & 0xFF;
        header[3] = (len >> 16) & 0xFF;
        header[4] = (len >> 8) & 0xFF;
        header[5] = len & 0xFF;

        send(controlSocket_, reinterpret_cast<const char*>(header), 6, 0);
        send(controlSocket_, json.data(), static_cast<int>(json.size()), 0);
    }
}

void PhoneCamClient::controlThreadFunc() {
    std::vector<uint8_t> buffer(65536);
    
    if (mode_ == TransportMode::UDP) {
        while (running_) {
            sockaddr_in sender{};
#if defined(_WIN32)
            int senderLen = sizeof(sender);
#else
            socklen_t senderLen = sizeof(sender);
#endif
            int bytes = recvfrom(controlSocket_, reinterpret_cast<char*>(buffer.data()), static_cast<int>(buffer.size() - 1), 0,
                                 reinterpret_cast<sockaddr*>(&sender), &senderLen);
            if (bytes <= 0) break;
            buffer[bytes] = '\0';
            handleControlMessage(std::string(reinterpret_cast<char*>(buffer.data()), bytes));
        }
    } else {
        while (running_) {
            uint8_t header[6];
            int bytesRead = 0;
            while (bytesRead < 6 && running_) {
                int bytes = recv(controlSocket_, reinterpret_cast<char*>(header + bytesRead), 6 - bytesRead, 0);
                if (bytes <= 0) {
                    running_ = false;
                    return;
                }
                bytesRead += bytes;
            }

            uint8_t channel = header[0];
            uint32_t length = (static_cast<uint32_t>(header[2]) << 24) |
                              (static_cast<uint32_t>(header[3]) << 16) |
                              (static_cast<uint32_t>(header[4]) << 8) |
                              static_cast<uint32_t>(header[5]);

            std::vector<uint8_t> payload(length);
            uint32_t payloadRead = 0;
            while (payloadRead < length && running_) {
                int bytes = recv(controlSocket_, reinterpret_cast<char*>(payload.data() + payloadRead), length - payloadRead, 0);
                if (bytes <= 0) {
                    running_ = false;
                    return;
                }
                payloadRead += bytes;
            }

            if (channel == 0x01) {
                handleControlMessage(std::string(reinterpret_cast<char*>(payload.data()), length));
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
        int bytes = recv(mediaSocket_, reinterpret_cast<char*>(buffer.data()), static_cast<int>(buffer.size()), 0);
        if (bytes <= 0) break;
        
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
        if (msg.status == "success") {
            sendJson(makeStartMessage());
        }
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
        if (playoutBuffer_.pop(frame, std::chrono::milliseconds(10))) {
            {
                std::lock_guard<std::mutex> lock(statsMutex_);
                framesReceivedInInterval_++;
            }

            auto now = std::chrono::steady_clock::now();
            if (!hasFirstTimestamp_) {
                firstRtpTimestamp_ = frame.rtpTimestamp;
                firstFrameTime_ = now;
                hasFirstTimestamp_ = true;
            }
            double elapsedSec = static_cast<int32_t>(frame.rtpTimestamp - firstRtpTimestamp_) / 90000.0;
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
