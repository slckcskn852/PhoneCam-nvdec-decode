#pragma once
#include <vector>
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
    explicit PlayoutBuffer(int targetDelayMs);
    ~PlayoutBuffer() = default;

    void push(std::vector<uint8_t> data, uint32_t rtpTimestamp, bool complete);
    bool pop(PlayoutFrame& frame, std::chrono::milliseconds timeout = std::chrono::milliseconds(10));
    void clear();
    void setTargetDelay(int delayMs);

private:
    int targetDelayMs_;
    std::vector<PlayoutFrame> queue_;
    std::mutex mutex_;
    std::condition_variable cond_;
};

} // namespace phonecam
