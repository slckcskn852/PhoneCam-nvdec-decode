# PhoneCam 4K60 Remake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild PhoneCamRedux into a phone-as-webcam system supporting low-latency 4K60 HEVC over WiFi (UDP) and USB cable fallback (TCP), with NACK retransmissions, jitter buffer, ABR, and a minimal UI.

**Architecture:** Streaming cores stay decoupled from UI. Android uses Camera2 + MediaCodec HEVC, iOS uses AVFoundation + VideoToolbox HEVC. Desktop receiver uses a shared C++ core (depacketizer, jitter buffer, NACK, JSON control client) with VideoToolbox on macOS and D3D11VA/NVDEC on Windows. Multiplexed TCP is used for USB cable fallback.

**Tech Stack:** Kotlin/Swift/C++, MediaCodec, VideoToolbox, AVFoundation, D3D11VA, FFmpeg, CMake, nlohmann/json (for C++ JSON).

---

### Task 1: Protocol Spec and Test Vectors (Already Completed)
- `docs/protocol-4k60.md` created.
- Conformance test vectors shipped in `docs/protocol-vectors/`.

---

### Task 2: Android Packetizer NACK History
Modify Android's packetizer to retain transmitted packets for retransmissions.

**Files:**
- Modify: `android/app/src/main/java/com/phonecam/stream4k/RtpHevcPacketizer.kt`
- Test: `android/app/src/test/java/com/phonecam/stream4k/RtpHevcPacketizerTest.kt`

- [ ] **Step 1: Write test for packet history retention**
  Create a test checking that packetize returns packets, and those packets can be retrieved by their sequence number.
  ```kotlin
  @Test
  fun testPacketHistory() {
      val packetizer = RtpHevcPacketizer()
      val nal = ByteArray(10) { it.toByte() }
      val packets = packetizer.packetize(nal, 0)
      assert(packets.isNotEmpty())
      val firstSeq = ((packets[0][2].toInt() and 0xFF) << 8) or (packets[0][3].toInt() and 0xFF)
      val retrieved = packetizer.getPacket(firstSeq)
      assert(retrieved != null)
      assert(retrieved!!.contentEquals(packets[0]))
  }
  ```
- [ ] **Step 2: Implement packet history in RtpHevcPacketizer**
  Modify `RtpHevcPacketizer` to keep a ring buffer of the last 256 packets.
  ```kotlin
  private val history = arrayOfNulls<ByteArray>(256)
  
  fun getPacket(seq: Int): ByteArray? {
      return history[seq % 256]?.takeIf {
          val packetSeq = ((it[2].toInt() and 0xFF) << 8) or (it[3].toInt() and 0xFF)
          packetSeq == seq
      }
  }
  
  // Inside writeRtpHeader:
  // After sequenceNumber is set and written to packet:
  // history[sequenceNumber % 256] = packet
  ```
- [ ] **Step 3: Run Android tests to verify**
  Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "com.phonecam.stream4k.RtpHevcPacketizerTest"`
  Expected: PASS

---

### Task 3: Android JSON Control Channel & ABR
Implement JSON control port 47822 supporting connect/start/stop/ping/nack/pli/feedback and ABR ladder step down.

**Files:**
- Modify: `android/app/src/main/java/com/phonecam/stream4k/Stream4kController.kt`
- Modify: `android/app/src/main/java/com/phonecam/stream4k/UdpStreamSender.kt`

- [ ] **Step 1: Add JSON Parsing dependency**
  Ensure Gson or org.json is available in `android/app/build.gradle`. (org.json is built-in on Android, we will use `org.json.JSONObject`).
- [ ] **Step 2: Update UdpStreamSender to support NACK retransmissions**
  Add a method `fun retransmitPacket(seq: Int)` that retrieves the packet from `packetizer.getPacket(seq)` and sends it to the target address over the UDP socket.
- [ ] **Step 3: Rewrite Stream4kController JSON handler**
  Listen for JSON packets on UDP 47822:
  - If `type == "connect"`, respond with `connect_ack` and select the best resolution from capabilities.
  - If `type == "start"`, start streaming.
  - If `type == "stop"`, stop streaming.
  - If `type == "ping"`, reply `pong`.
  - If `type == "nack"`, call `sender.retransmitPacket(seq)` for each sequence number in the request.
  - If `type == "pli"`, call `encoder.requestKeyFrame()`.
  - If `type == "feedback"`, read `loss_fraction`. If `loss_fraction > 0.02`, reduce bitrate. If at floor, step down the ladder.
  - Implement keepalive: if no packet received for 5s, call `stopStreaming()`.

---

### Task 4: Android USB TCP Fallback
Multiplex control and media over a single TCP connection for USB cable fallback.

**Files:**
- Create: `android/app/src/main/java/com/phonecam/stream4k/TcpStreamSender.kt`
- Modify: `android/app/src/main/java/com/phonecam/stream4k/Stream4kController.kt`

- [ ] **Step 1: Implement TcpStreamSender**
  It should maintain a TCP socket connected to the client (or accepting a client).
  When sending a packet, it prefixes it with:
  - Byte 0: Channel (0x01 for Control, 0x02 for Media)
  - Byte 1: Reserved (0x00)
  - Bytes 2-5: 32-bit big-endian length.
- [ ] **Step 2: Add TCP listening in Stream4kController**
  Listen on a TCP ServerSocket on port 47822. If a client connects, swap the transport to TCP mode. Handle incoming multiplexed frames:
  - Channel 0x01: parse control JSON message.
  - Channel 0x02: invalid (sender shouldn't send media to phone).

---

### Task 5: Desktop Receiver Shared Core (depacketizer, jitter buffer, control client)
Create a shared C++ core managing RTP HEVC depacketization, reordering, NACK, jitter playout, and JSON control.

**Files:**
- Create: `desktop/core/src/receiver_core.cpp`
- Create: `desktop/core/include/phonecam/receiver_core.h`
- Modify: `desktop/windows/src/rtp_hevc.cpp`
- Modify: `desktop/windows/src/rtp_hevc.h`

- [ ] **Step 1: Modify rtp_hevc.h/cpp to support NACK callbacks**
  When a gap in sequence numbers is detected in `RtpHevcDepacketizer::feedPacket()`, call a `NackCallback` requesting retransmission.
- [ ] **Step 2: Implement Jitter Buffer**
  A queue sorting decoded frames or access units by timestamp, playing them out after a configurable target delay (e.g. 50 ms).
- [ ] **Step 3: Implement JSON Control Client**
  Send JSON `connect` request, receive `connect_ack`, send `start`, and launch a keepalive ping loop.
- [ ] **Step 4: Support TCP Cable Ingest**
  Read 6-byte multiplexed headers. Decode control JSON or feed media payloads directly to the HEVC depacketizer.

---

### Task 6: macOS Receiver (VideoToolbox Decode + CMIO Target)
Implement VideoToolbox decode, Cocoa preview window, and CMIO Camera Extension target.

**Files:**
- Create: `desktop/macos/CMakeLists.txt`
- Create: `desktop/macos/src/videotoolbox_decoder.cpp`
- Create: `desktop/macos/src/cmio_extension.mm`

- [ ] **Step 1: Implement VideoToolbox decoder**
  Use `VTDecompressionSessionCreate` to decode Annex-B H.265 frames to CVImageBuffer/CVPixelBuffer.
- [ ] **Step 2: Implement Preview & CMIO extension**
  Expose a clean frame-callback API. The Cocoa preview and CMIO camera extension consume it.
- [ ] **Step 3: Add macOS build flags in desktop/CMakeLists.txt**

---

### Task 7: Windows Receiver (D3D11VA/NVDEC + Softcam)
Implement D3D11VA/NVDEC decode, Softcam integration, and CTest configurations.

**Files:**
- Modify: `desktop/windows/CMakeLists.txt`
- Modify: `desktop/windows/src/main.cpp`

- [ ] **Step 1: Implement D3D11VA decode fallback**
  Configure FFmpeg to use hwaccel `d3d11va` or `nvdec`.
- [ ] **Step 2: Integrate with Softcam sink**
  Send decoded BGR24 frames to `scSendFrame`.
- [ ] **Step 3: Add test cases to CTest**

---

### Task 8: iOS Sender Core (AVFoundation + VideoToolbox)
Create new iOS Xcode/SwiftPM project capturing 4K60, encoding via VideoToolbox, and packetizing to RTP HEVC with NACK and JSON control in Swift.

**Files:**
- Create: `ios/PhoneCam/PhoneCam.xcodeproj`
- Create: `ios/PhoneCam/PhoneCam/RtpSwiftPacketizer.swift`
- Create: `ios/PhoneCam/PhoneCam/ControlClient.swift`

- [ ] **Step 1: Port RTP Packetizer to Swift**
  Unit test against `docs/protocol-vectors/rtp_single_nal.hex` and `rtp_fu_start.hex` in Swift unit tests.
- [ ] **Step 2: Add AVFoundation & VideoToolbox capture pipeline**
  Configure HEVC profile, low latency, keyframe forcing.

---

### Task 9: UI Wiring and Validation
Wire resolution pickers and stats overlays.

**Files:**
- Modify: `android/app/src/main/java/com/phonecam/RtspMainActivity.kt`
- Modify: `android/app/src/main/res/layout/activity_rtsp.xml`
- Create: `docs/verification-4k60.md`

- [ ] **Step 1: Wire Mode Selection and Status in Android UI**
- [ ] **Step 2: Run Synthetic Soak Test and write Verification Results**
  Measure throughput, latency, NACK recovery under 2% drop rate. Document in `docs/verification-4k60.md`.
