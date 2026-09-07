#include "playout_buffer.h"
#include <algorithm>

namespace phonecam {

PlayoutBuffer::PlayoutBuffer(int targetDelayMs, size_t maxFrames, size_t maxBytes, int maxAgeMs)
    : targetDelayMs_(std::clamp(targetDelayMs, 0, 1000)),
      maxFrames_(std::max(size_t{1}, maxFrames)), maxBytes_(maxBytes), maxAge_(std::max(1, maxAgeMs)) {}

bool PlayoutBuffer::push(std::vector<uint8_t> data, uint32_t rtpTimestamp, bool complete) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (data.size() > maxBytes_) return false;
    bool retainedAll = true;
    const auto now = std::chrono::steady_clock::now();
    // A deliberate fixed playout delay is not stale backlog. Leave 20 ms of scheduling headroom.
    const auto ageLimit = std::max(maxAge_, std::chrono::milliseconds(targetDelayMs_ + 20));
    while (!queue_.empty() && (now - queue_.front().arrivalTime > ageLimit || queue_.size() >= maxFrames_ || queuedBytes_ > maxBytes_ - data.size())) {
        queuedBytes_ -= queue_.front().data.size();
        queue_.pop_front();
        retainedAll = false;
    }
    queuedBytes_ += data.size();
    PlayoutFrame frame;
    frame.data = std::move(data);
    frame.rtpTimestamp = rtpTimestamp;
    frame.complete = complete;
    frame.arrivalTime = std::chrono::steady_clock::now();
    frame.playoutTime = frame.arrivalTime + std::chrono::milliseconds(targetDelayMs_);
    
    auto it = std::upper_bound(queue_.begin(), queue_.end(), rtpTimestamp,
        [](uint32_t ts, const PlayoutFrame& f) {
            return static_cast<int32_t>(ts - f.rtpTimestamp) < 0;
        });
    queue_.insert(it, std::move(frame));
    cond_.notify_one();
    return retainedAll;
}

bool PlayoutBuffer::pop(PlayoutFrame& frame, std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    for (;;) {
        const auto now = std::chrono::steady_clock::now();
        if (!queue_.empty() && now >= queue_.front().playoutTime) {
            queuedBytes_ -= queue_.front().data.size();
            frame = std::move(queue_.front());
            queue_.pop_front();
            return true;
        }
        if (now >= deadline) return false;
        cond_.wait_until(lock, queue_.empty() ? deadline : std::min(deadline, queue_.front().playoutTime));
    }
}

void PlayoutBuffer::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.clear();
    queuedBytes_ = 0;
    cond_.notify_all();
}

void PlayoutBuffer::setTargetDelay(int delayMs) {
    std::lock_guard<std::mutex> lock(mutex_);
    targetDelayMs_ = std::clamp(delayMs, 0, 1000);
    for (auto& frame : queue_) frame.playoutTime = frame.arrivalTime + std::chrono::milliseconds(targetDelayMs_);
    cond_.notify_all();
}

size_t PlayoutBuffer::queuedBytes() { std::lock_guard<std::mutex> lock(mutex_); return queuedBytes_; }
size_t PlayoutBuffer::queuedFrames() { std::lock_guard<std::mutex> lock(mutex_); return queue_.size(); }

} // namespace phonecam
