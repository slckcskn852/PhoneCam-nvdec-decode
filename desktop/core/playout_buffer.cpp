#include "playout_buffer.h"
#include <algorithm>

namespace phonecam {

PlayoutBuffer::PlayoutBuffer(int targetDelayMs) : targetDelayMs_(targetDelayMs) {}

void PlayoutBuffer::push(std::vector<uint8_t> data, uint32_t rtpTimestamp, bool complete) {
    std::lock_guard<std::mutex> lock(mutex_);
    PlayoutFrame frame;
    frame.data = std::move(data);
    frame.rtpTimestamp = rtpTimestamp;
    frame.complete = complete;
    frame.arrivalTime = std::chrono::steady_clock::now();
    frame.playoutTime = frame.arrivalTime + std::chrono::milliseconds(targetDelayMs_);
    
    auto it = std::upper_bound(queue_.begin(), queue_.end(), rtpTimestamp,
        [](uint32_t ts, const PlayoutFrame& f) {
            return ts < f.rtpTimestamp;
        });
    queue_.insert(it, std::move(frame));
    cond_.notify_one();
}

bool PlayoutBuffer::pop(PlayoutFrame& frame, std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (queue_.empty()) {
        cond_.wait_for(lock, timeout);
    }
    if (queue_.empty()) {
        return false;
    }
    
    auto now = std::chrono::steady_clock::now();
    if (now >= queue_.front().playoutTime) {
        frame = std::move(queue_.front());
        queue_.erase(queue_.begin());
        return true;
    }
    
    auto waitTime = queue_.front().playoutTime - now;
    if (waitTime > timeout) {
        waitTime = timeout;
    }
    cond_.wait_for(lock, waitTime);
    
    now = std::chrono::steady_clock::now();
    if (!queue_.empty() && now >= queue_.front().playoutTime) {
        frame = std::move(queue_.front());
        queue_.erase(queue_.begin());
        return true;
    }
    return false;
}

void PlayoutBuffer::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.clear();
}

void PlayoutBuffer::setTargetDelay(int delayMs) {
    std::lock_guard<std::mutex> lock(mutex_);
    targetDelayMs_ = delayMs;
}

} // namespace phonecam
