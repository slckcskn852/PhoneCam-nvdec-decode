# 4K60 Verification Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 4K60 HEVC verification gaps on macOS and Windows by implementing proper CLI runners, a synthetic 4K60 loopback test harness, shared discovery/conformance CTest integration, and a Windows D3D11VA hwaccel decoder.

**Architecture:** Use a shared discovery layer in the core library and match CLI arguments on both targets. The macOS target uses VideoToolbox with a headless/null-sink path, and the Windows target uses FFmpeg with D3D11VA.

**Tech Stack:** C++20, CMake, VideoToolbox (macOS), FFmpeg/D3D11VA (Windows), bash scripts.

---

### Task 1: Promote Discovery Protocol to Shared Core

**Files:**
- Create: `desktop/core/discovery.h`
- Create: `desktop/core/discovery.cpp`
- Modify: `desktop/CMakeLists.txt`
- Modify: `desktop/windows/src/main.cpp`

- [ ] **Step 1: Write discovery.h**
  Create a shared interface for the UDP auto-discovery beacon parsing and target resolution.
  ```cpp
  #pragma once
  #include <string>
  #include <vector>

  namespace phonecam {

  struct DiscoveryDevice {
      std::string url;
      std::string senderIp;
      std::string deviceName;
      int width = 0;
      int height = 0;
      int fps = 0;
      int bitrate = 0;
      std::string pairCode;
  };

  class PhoneCamDiscovery {
  public:
      static std::vector<DiscoveryDevice> runDiscovery(int timeoutMs, const std::string& expectedPairCode);
  };

  } // namespace phonecam
  ```

- [ ] **Step 2: Write discovery.cpp**
  Copy/port discovery socket implementation using `#ifdef _WIN32` for WSAStartup / winsock vs POSIX socket functions.

- [ ] **Step 3: Update desktop/CMakeLists.txt**
  Include `core/discovery.cpp` and `core/discovery.h` under `phonecam-core` library.

- [ ] **Step 4: Update desktop/windows/src/main.cpp**
  Include `"discovery.h"` and replace inline discovery code with `phonecam::PhoneCamDiscovery::runDiscovery`. Remove old duplicated discovery helper definitions.

- [ ] **Step 5: Verify build**
  Run: `cmake -B build/macos -DPHONECAM_TARGET=macos && cmake --build build/macos`
  Expected: Success

---

### Task 2: Implement macOS Receiver CLI and Headless Statistics

**Files:**
- Modify: `desktop/macos/src/main.mm`

- [ ] **Step 1: Implement argument parser and stats printing in main.mm**
  Add CLI parser to `main.mm` supporting:
  - `--connect <host>` (default 127.0.0.1)
  - `--width <w>`, `--height <h>`, `--fps <fps>` (default 3840x2160@60)
  - `--tcp`
  - `--headless`
  - `--duration <s>`
  - `--stats-interval <sec>` (default 1.0)
  Print statistics every interval and print JSON summary at exit. Exit with code 1 if average decode FPS < 55.0 or loss_percent >= 1.0%.

- [ ] **Step 2: Add support for headless (no-GUI) execution**
  If `--headless` is set, do not call `NSApplicationMain`. Instantiate `PhoneCamClient`, configure its callback to decode frames using `VideoToolboxDecoder` into a null sink, and wait/sleep on the main thread for `--duration` seconds, handling `SIGINT` gracefully.

- [ ] **Step 3: Compile and check**
  Run: `cmake --build build/macos`
  Expected: Success

---

### Task 3: Build Synthetic Soak Test Sender and Loopback Test Harness

**Files:**
- Create: `desktop/tests/phonecam_soak_sender.cpp`
- Modify: `desktop/CMakeLists.txt`
- Create: `scripts/soak_4k60.sh`

- [ ] **Step 1: Write phonecam_soak_sender.cpp**
  Implement the UDP control handshake listener on port 47822 and media sender.
  Support packetizing an HEVC file into RTP packets conforming to RFC 7798 (implementing a simple RTP HEVC packetizer with NACK retransmission from a 512-packet history).
  Support `--inject-loss <pct>` to drop packets randomly.

- [ ] **Step 2: Update desktop/CMakeLists.txt**
  Add `phonecam-soak-sender` executable and add a CTest target.

- [ ] **Step 3: Create scripts/soak_4k60.sh**
  Write bash script to:
  1. Generate a 5-second 4K60 HEVC video using ffmpeg/hevc_videotoolbox.
  2. Run the receiver (headless, 60s) and sender.
  3. Execute twice: clean (0% loss) and 2% loss.
  4. Fail if decode FPS < 55 or post-NACK loss >= 1%.

- [ ] **Step 4: Run tests**
  Run: `ctest --test-dir build/macos --output-on-failure`
  Expected: Success

---

### Task 4: Migrate Windows Receiver to core and D3D11VA

**Files:**
- Delete: `desktop/windows/src/rtp_hevc.cpp`
- Delete: `desktop/windows/src/rtp_hevc.h`
- Create: `desktop/windows/src/rtsp_ingest.h`
- Create: `desktop/windows/src/rtsp_ingest.cpp`
- Modify: `desktop/windows/src/main.cpp`
- Modify: `desktop/windows/CMakeLists.txt`

- [ ] **Step 1: Delete duplicate RTP HEVC files**
  Remove `desktop/windows/src/rtp_hevc.cpp` and `desktop/windows/src/rtp_hevc.h` from directory.

- [ ] **Step 2: Extract legacy RTSP FFmpeg ingest**
  Create `rtsp_ingest.h` and `rtsp_ingest.cpp`, moving the RTSP pull loop from `main.cpp` into this module.

- [ ] **Step 3: Update main.cpp with F1 CLI and D3D11VA decode backend**
  - Implement F1 matching CLI arguments.
  - Implement `PhoneCamClient` UDP loop.
  - Set up FFmpeg HEVC decoding: if running on Windows (`_WIN32`), configure with `AV_HWDEVICE_TYPE_D3D11VA` hwaccel. Otherwise, fall back to CPU decoding.
  - Feed the decoded frames into the `FrameSink` pipeline.

- [ ] **Step 4: Update CMakeLists.txt and compile-check on Mac**
  Run: `cmake -B build/windows -DPHONECAM_TARGET=windows -DFFMPEG_ROOT=/opt/homebrew/opt/ffmpeg && cmake --build build/windows`
  Expected: Success
