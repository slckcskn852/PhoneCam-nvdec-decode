#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <vector>

namespace phonecam {

// RFC 7798 (HEVC over RTP) depacketizer with a sequence reorder buffer.
//
// Pure C++17: no sockets, no FFmpeg. Feed one UDP datagram per feedPacket()
// call; completed access units are delivered through the AccessUnitCallback
// as Annex B byte streams (00 00 00 01 prefixed NAL units).
//
// feedPacket() and the flush methods are designed for a single caller thread
// (the UDP receive thread). statsSnapshotAndReset() is thread-safe and may be
// called from a different thread once per reporting interval.
class RtpHevcDepacketizer {
public:
  struct Stats {
    uint64_t packetsReceived = 0;  // valid RTP packets seen
    uint64_t packetsLost = 0;      // sequence numbers declared lost by the reorder buffer
    uint64_t fusDropped = 0;       // FU fragments discarded because a fragment went missing
    uint64_t framesEmitted = 0;    // access units delivered to the callback
    uint64_t bytesReceived = 0;    // UDP payload bytes including RTP headers
    uint64_t nackRecoveries = 0;   // actual NACKed packets recovered
    double jitter = 0.0;           // RFC 3550 interarrival jitter estimate, in 90 kHz units
  };

  using AccessUnitCallback =
    std::function<void(const uint8_t* data, size_t len, uint32_t rtpTimestamp, bool completeAu)>;
  using NackCallback = std::function<void(const std::vector<uint16_t>& seqs)>;

  explicit RtpHevcDepacketizer(size_t reorderCapacity = 1024, uint32_t gapTimeoutPackets = 256);

  void setAccessUnitCallback(AccessUnitCallback callback);
  void setNackCallback(NackCallback callback);

  // Feed one received UDP datagram. Malformed datagrams are ignored.
  void feedPacket(const uint8_t* data, size_t len);

  // Emit the pending access unit if it has been waiting more than ~50 ms, so
  // a lost marker packet cannot stall the stream. Emitted with completeAu=false.
  void flushStaleAccessUnit();

  // Release every buffered packet in order and emit any pending access unit.
  void flushAll();

  // Counters since the previous call. The jitter estimate is a running state
  // variable and is not reset.
  Stats statsSnapshotAndReset();

private:
  struct BufferedPacket {
    uint32_t timestamp = 0;
    bool marker = false;
    std::vector<uint8_t> payload;
  };

  void releaseReady();
  void processPacket(const BufferedPacket& packet, bool contiguous);
  void processFu(const std::vector<uint8_t>& payload, bool alreadyAborted);
  void abortFu();
  void appendNal(const uint8_t* data, size_t len);
  void emitAccessUnit(bool complete);
  void updateJitterLocked(uint32_t timestamp, std::chrono::steady_clock::time_point arrival);

  AccessUnitCallback callback_;
  const size_t reorderCapacity_;
  const uint32_t gapTimeoutPackets_;

  // Reorder buffer keyed by extended 32-bit sequence number.
  std::map<uint32_t, BufferedPacket> pending_;
  bool haveRange_ = false;
  uint32_t nextReleaseSeq_ = 0;
  uint32_t highestSeq_ = 0;
  bool haveLastReleased_ = false;
  uint32_t lastReleasedSeq_ = 0;

  // Current access unit under assembly.
  std::vector<uint8_t> auBuffer_;
  bool auActive_ = false;
  uint32_t auTimestamp_ = 0;
  std::chrono::steady_clock::time_point auStarted_{};

  // Fragmentation unit (type 49) reassembly state.
  bool fuActive_ = false;
  uint8_t fuHeader_[2] = {0, 0};
  std::vector<uint8_t> fuBuffer_;

  mutable std::mutex statsMutex_;
  Stats stats_;
  bool haveTransit_ = false;
  uint32_t lastTimestamp_ = 0;
  double lastArrival90k_ = 0.0;

  NackCallback nackCallback_;
  std::map<uint32_t, std::chrono::steady_clock::time_point> nackSentTimes_;
  std::map<uint32_t, int> nackRetries_;
};

} // namespace phonecam
