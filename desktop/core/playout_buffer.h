#pragma once
#include <vector>
#include <deque>
#include <cstdint>
#include <chrono>
#include <mutex>
#include <condition_variable>

namespace phonecam {

struct PlayoutFrame {
    std::vector<uint8_t> data;
    uint32_t rtpTimestamp;
    bool complete;
    std::chrono::steady_clock::time_point playoutTime;
    std::chrono::steady_clock::time_point arrivalTime;
};

class PlayoutBuffer {
public:
    explicit PlayoutBuffer(int targetDelayMs, size_t maxFrames = 32, size_t maxBytes = 32 * 1024 * 1024, int maxAgeMs = 80);
    ~PlayoutBuffer() = default;

    bool push(std::vector<uint8_t> data, uint32_t rtpTimestamp, bool complete);
    size_t queuedBytes();
    size_t queuedFrames();
    bool pop(PlayoutFrame& frame, std::chrono::milliseconds timeout = std::chrono::milliseconds(10));
    void clear();
    void setTargetDelay(int delayMs);

private:
    int targetDelayMs_;
    std::deque<PlayoutFrame> queue_;
    const size_t maxFrames_;
    const size_t maxBytes_;
    const std::chrono::milliseconds maxAge_;
    size_t queuedBytes_ = 0;
    std::mutex mutex_;
    std::condition_variable cond_;
};

} // namespace phonecam
