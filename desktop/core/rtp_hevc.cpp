#include "rtp_hevc.h"

#include <cmath>
#include <cstring>

namespace phonecam {
namespace {

constexpr std::chrono::milliseconds kAuTimeout{50};
constexpr uint8_t kStartCode[4] = {0x00, 0x00, 0x00, 0x01};

struct RtpView {
  uint16_t seq = 0;
  uint32_t timestamp = 0;
  bool marker = false;
  const uint8_t* payload = nullptr;
  size_t payloadLen = 0;
};

// Parses a 12-byte RTP header, skipping CSRC entries and any header
// extension (X bit) and honoring the padding bit. V must be 2.
bool parseRtp(const uint8_t* data, size_t len, RtpView& view) {
  if (!data || len > 65535 || len < 12 || (data[0] >> 6) != 2) {
    return false;
  }
  const size_t csrcCount = data[0] & 0x0F;
  const bool hasExtension = (data[0] & 0x10) != 0;
  const bool hasPadding = (data[0] & 0x20) != 0;

  size_t headerLen = 12 + csrcCount * 4;
  if (len < headerLen) {
    return false;
  }
  if (hasExtension) {
    if (len < headerLen + 4) {
      return false;
    }
    const size_t extWords = (static_cast<size_t>(data[headerLen + 2]) << 8) | data[headerLen + 3];
    headerLen += 4 + extWords * 4;
    if (len < headerLen) {
      return false;
    }
  }

  view.marker = (data[1] & 0x80) != 0;
  view.seq = static_cast<uint16_t>((data[2] << 8) | data[3]);
  view.timestamp = (static_cast<uint32_t>(data[4]) << 24) |
                   (static_cast<uint32_t>(data[5]) << 16) |
                   (static_cast<uint32_t>(data[6]) << 8) |
                   static_cast<uint32_t>(data[7]);

  size_t payloadLen = len - headerLen;
  if (hasPadding && payloadLen > 0) {
    const uint8_t padding = data[len - 1];
    if (padding == 0 || padding > payloadLen) {
      return false;
    }
    payloadLen -= padding;
  }

  view.payload = data + headerLen;
  view.payloadLen = payloadLen;
  return true;
}

} // namespace

RtpHevcDepacketizer::RtpHevcDepacketizer(size_t reorderCapacity, uint32_t gapTimeoutPackets)
  : reorderCapacity_(reorderCapacity == 0 ? 1 : reorderCapacity),
    gapTimeoutPackets_(gapTimeoutPackets == 0 ? 1 : gapTimeoutPackets) {}

void RtpHevcDepacketizer::setAccessUnitCallback(AccessUnitCallback callback) {
  callback_ = std::move(callback);
}

void RtpHevcDepacketizer::setNackCallback(NackCallback callback) {
  nackCallback_ = std::move(callback);
}

void RtpHevcDepacketizer::feedPacket(const uint8_t* data, size_t len) {
  RtpView view;
  if (!parseRtp(data, len, view)) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    ++stats_.packetsReceived;
    stats_.bytesReceived += len;
    updateJitterLocked(view.timestamp, now);
  }

  // Extend the 16-bit sequence number to 32 bits using signed wrap-safe
  // deltas from the highest sequence number seen so far.
  uint32_t ext;
  if (!haveRange_) {
    haveRange_ = true;
    ext = view.seq;
    highestSeq_ = ext;
    nextReleaseSeq_ = ext;
  } else {
    const int16_t delta = static_cast<int16_t>(view.seq - static_cast<uint16_t>(highestSeq_));
    ext = highestSeq_ + delta;
    if (delta > 0) {
      highestSeq_ = ext;
    }
  }

  // Detect and count actual NACK recovery
  bool isNackRecovery = false;
  auto nackIt = nackSentTimes_.find(ext);
  if (nackIt != nackSentTimes_.end()) {
    isNackRecovery = true;
    nackSentTimes_.erase(nackIt);
    nackRetries_.erase(ext);
  }

  if (isNackRecovery) {
    std::lock_guard<std::mutex> lock(statsMutex_);
    ++stats_.nackRecoveries;
  }

  // Check for gaps and request NACKs
  if (ext > nextReleaseSeq_ && nackCallback_) {
    std::vector<uint16_t> missingSeqs;
    const auto nowTime = std::chrono::steady_clock::now();
    uint32_t giveUpUntil = nextReleaseSeq_;
    for (uint32_t s = nextReleaseSeq_; s < ext && s - nextReleaseSeq_ < gapTimeoutPackets_; ++s) {
      if (pending_.find(s) == pending_.end()) {
        auto it = nackSentTimes_.find(s);
        if (it == nackSentTimes_.end()) {
          missingSeqs.push_back(static_cast<uint16_t>(s & 0xFFFF));
          nackSentTimes_[s] = nowTime;
          nackRetries_[s] = 1;
        } else if ((nowTime - it->second) > std::chrono::milliseconds(15)) {
          if (nackRetries_[s] >= 5) {
            if (s + 1 > giveUpUntil) {
              giveUpUntil = s + 1;
            }
          } else {
            missingSeqs.push_back(static_cast<uint16_t>(s & 0xFFFF));
            it->second = nowTime;
            nackRetries_[s]++;
          }
        }
      }
    }
    if (giveUpUntil > nextReleaseSeq_) {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.packetsLost += (giveUpUntil - nextReleaseSeq_);
      nextReleaseSeq_ = giveUpUntil;
    }
    if (!missingSeqs.empty()) {
      nackCallback_(missingSeqs);
    }
  }

  // Packets older than the next expected release arrived after their gap was
  // already declared lost; drop them so pending_ only holds future releases.
  if (static_cast<int32_t>(ext - nextReleaseSeq_) < 0) {
    return;
  }

  BufferedPacket packet;
  packet.timestamp = view.timestamp;
  packet.marker = view.marker;
  packet.payload.assign(view.payload, view.payload + view.payloadLen);
  pending_.emplace(ext, std::move(packet));
  releaseReady();
}

void RtpHevcDepacketizer::releaseReady() {
  // Declare a gap lost once enough newer packets have piled up behind it.
  if (!pending_.empty() && highestSeq_ - nextReleaseSeq_ >= gapTimeoutPackets_) {
    const auto first = pending_.begin();
    if (first->first > nextReleaseSeq_) {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.packetsLost += first->first - nextReleaseSeq_;
      nextReleaseSeq_ = first->first;
    }
  }

  // Release the contiguous run in order.
  while (!pending_.empty()) {
    auto it = pending_.find(nextReleaseSeq_);
    if (it == pending_.end()) {
      break;
    }
    const bool contiguous = haveLastReleased_ && it->first == lastReleasedSeq_ + 1;
    processPacket(it->second, contiguous);
    haveLastReleased_ = true;
    lastReleasedSeq_ = it->first;
    pending_.erase(it);
    ++nextReleaseSeq_;
  }

  // Safety valve: never let the reorder buffer grow past capacity.
  while (pending_.size() > reorderCapacity_) {
    auto it = pending_.begin();
    if (it->first > nextReleaseSeq_) {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.packetsLost += it->first - nextReleaseSeq_;
      nextReleaseSeq_ = it->first;
    }
    const bool contiguous = haveLastReleased_ && it->first == lastReleasedSeq_ + 1;
    processPacket(it->second, contiguous);
    haveLastReleased_ = true;
    lastReleasedSeq_ = it->first;
    pending_.erase(it);
    ++nextReleaseSeq_;
  }

  // Clean up NACK tracking
  while (!nackSentTimes_.empty() && nackSentTimes_.begin()->first < nextReleaseSeq_) {
    nackRetries_.erase(nackSentTimes_.begin()->first);
    nackSentTimes_.erase(nackSentTimes_.begin());
  }
}

void RtpHevcDepacketizer::processPacket(const BufferedPacket& packet, bool contiguous) {
  if (packet.payload.size() < 2) {
    return;
  }

  // A gap in the released sequence breaks any in-progress fragmentation unit.
  bool fuAborted = false;
  if (!contiguous && fuActive_) {
    abortFu();
    fuAborted = true;
  }

  // A newer RTP timestamp closes the previous access unit even when its
  // marker packet was lost.
  if (auActive_ && packet.timestamp != auTimestamp_) {
    emitAccessUnit(false);
  }
  if (!auActive_) {
    auActive_ = true;
    auTimestamp_ = packet.timestamp;
    auStarted_ = std::chrono::steady_clock::now();
  }

  if (!contiguous && haveLastReleased_) auDamaged_ = true;

  const uint8_t nalType = (packet.payload[0] >> 1) & 0x3F;
  if (nalType <= 47) {
    // Single NAL unit packet.
    appendNal(packet.payload.data(), packet.payload.size());
  } else if (nalType == 48) {
    // Aggregation packet: 2-byte length-prefixed sub-NALs.
    size_t offset = 2;
    while (offset + 2 <= packet.payload.size()) {
      const size_t nalLen = (static_cast<size_t>(packet.payload[offset]) << 8) |
                            packet.payload[offset + 1];
      offset += 2;
      if (nalLen < 2 || offset + nalLen > packet.payload.size()) {
        auDamaged_ = true;
        break;
      }
      appendNal(packet.payload.data() + offset, nalLen);
      offset += nalLen;
    }
  } else if (nalType == 49) {
    processFu(packet.payload, fuAborted);
  }
  // Types 50+ (PACI and beyond) carry no slice data; ignore them.

  if (packet.marker) {
    emitAccessUnit(true);
  }
}

void RtpHevcDepacketizer::processFu(const std::vector<uint8_t>& payload, bool alreadyAborted) {
  if (payload.size() < 4) {
    auDamaged_ = true;
    return;
  }
  const uint8_t fuHeader = payload[2];
  const bool start = (fuHeader & 0x80) != 0;
  const bool end = (fuHeader & 0x40) != 0;

  if (start) {
    if (fuActive_) {
      abortFu();  // previous FU never saw its end fragment
    }
    // Rebuild the 2-byte NAL header: F and nuh_layer_id bits from the FU
    // indicator, nal_unit_type from the FU header.
    fuHeader_[0] = static_cast<uint8_t>((payload[0] & 0x81) | ((fuHeader & 0x3F) << 1));
    fuHeader_[1] = payload[1];
    fuBuffer_.assign(payload.begin() + 3, payload.end());
    fuActive_ = true;
  } else if (fuActive_) {
    if (fuBuffer_.size() + payload.size() - 3 > kMaxAccessUnitBytes - 6) {
      abortFu();
      return;
    }
    fuBuffer_.insert(fuBuffer_.end(), payload.begin() + 3, payload.end());
  } else {
    // Middle/end fragment with no live start fragment: this FU sequence is
    // unrecoverable. Skip the count when the discontinuity abort above
    // already accounted for it.
    if (!alreadyAborted) {
      std::lock_guard<std::mutex> lock(statsMutex_);
      ++stats_.fusDropped;
    }
    return;
  }

  if (end && fuActive_) {
    if (auBuffer_.size() + fuBuffer_.size() + 6 > kMaxAccessUnitBytes) {
      abortFu();
      return;
    }
    auBuffer_.insert(auBuffer_.end(), std::begin(kStartCode), std::end(kStartCode));
    auBuffer_.push_back(fuHeader_[0]);
    auBuffer_.push_back(fuHeader_[1]);
    auBuffer_.insert(auBuffer_.end(), fuBuffer_.begin(), fuBuffer_.end());
    fuActive_ = false;
    fuBuffer_.clear();
  }
}

void RtpHevcDepacketizer::abortFu() {
  if (!fuActive_) {
    return;
  }
  fuActive_ = false;
  auDamaged_ = true;
  fuBuffer_.clear();
  std::lock_guard<std::mutex> lock(statsMutex_);
  ++stats_.fusDropped;
}

void RtpHevcDepacketizer::appendNal(const uint8_t* data, size_t len) {
  if (len < 2 || len > kMaxAccessUnitBytes - 4 || auBuffer_.size() > kMaxAccessUnitBytes - 4 - len) {
    auDamaged_ = true;
    return;
  }
  auBuffer_.insert(auBuffer_.end(), std::begin(kStartCode), std::end(kStartCode));
  auBuffer_.insert(auBuffer_.end(), data, data + len);
}

void RtpHevcDepacketizer::emitAccessUnit(bool complete) {
  if (!auActive_) {
    return;
  }
  if (fuActive_) {
    // An FU spanning an access-unit boundary can never complete.
    abortFu();
  }
  if ((!auBuffer_.empty() || auDamaged_) && callback_) {
    callback_(auBuffer_.data(), auBuffer_.size(), auTimestamp_, complete && !auDamaged_);
    std::lock_guard<std::mutex> lock(statsMutex_);
    ++stats_.framesEmitted;
  }
  auBuffer_.clear();
  auActive_ = false;
  auDamaged_ = false;
}

void RtpHevcDepacketizer::flushStaleAccessUnit() {
  if (!auActive_) {
    return;
  }
  if (std::chrono::steady_clock::now() - auStarted_ >= kAuTimeout) {
    emitAccessUnit(false);
  }
}

void RtpHevcDepacketizer::flushAll() {
  while (!pending_.empty()) {
    auto it = pending_.begin();
    if (it->first > nextReleaseSeq_) {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.packetsLost += it->first - nextReleaseSeq_;
      nextReleaseSeq_ = it->first;
    }
    const bool contiguous = haveLastReleased_ && it->first == lastReleasedSeq_ + 1;
    processPacket(it->second, contiguous);
    haveLastReleased_ = true;
    lastReleasedSeq_ = it->first;
    pending_.erase(it);
    ++nextReleaseSeq_;
  }
  emitAccessUnit(false);
  nackSentTimes_.clear();
  nackRetries_.clear();
}

void RtpHevcDepacketizer::reset() {
  pending_.clear(); nackSentTimes_.clear(); nackRetries_.clear();
  auBuffer_.clear(); fuBuffer_.clear();
  haveRange_ = haveLastReleased_ = auActive_ = auDamaged_ = fuActive_ = haveTransit_ = false;
  nextReleaseSeq_ = highestSeq_ = lastReleasedSeq_ = 0;
  std::lock_guard<std::mutex> lock(statsMutex_);
  stats_ = {};
}

RtpHevcDepacketizer::Stats RtpHevcDepacketizer::statsSnapshotAndReset() {
  std::lock_guard<std::mutex> lock(statsMutex_);
  Stats snapshot = stats_;
  stats_.packetsReceived = 0;
  stats_.packetsLost = 0;
  stats_.fusDropped = 0;
  stats_.framesEmitted = 0;
  stats_.bytesReceived = 0;
  stats_.nackRecoveries = 0;
  // stats_.jitter keeps its running estimate.
  return snapshot;
}

void RtpHevcDepacketizer::updateJitterLocked(uint32_t timestamp,
                                             std::chrono::steady_clock::time_point arrival) {
  // RFC 3550 appendix A.8: interarrival jitter in timestamp (90 kHz) units.
  const double arrival90k =
    std::chrono::duration<double>(arrival.time_since_epoch()).count() * 90000.0;
  if (haveTransit_) {
    const int32_t timestampDiff = static_cast<int32_t>(timestamp - lastTimestamp_);
    const double d = (arrival90k - lastArrival90k_) - static_cast<double>(timestampDiff);
    stats_.jitter += (std::fabs(d) - stats_.jitter) / 16.0;
  }
  haveTransit_ = true;
  lastTimestamp_ = timestamp;
  lastArrival90k_ = arrival90k;
}

} // namespace phonecam
