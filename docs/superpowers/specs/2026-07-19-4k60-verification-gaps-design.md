# 4K60 HEVC PhoneCam Verification Gaps Design Specification

This document details the architectural design and implementation plan to close the verification gaps in the PhoneCam 4K60 HEVC stream receiver and sender.

---

## 1. Objectives

*   **F1. macOS Receiver CLI & Headless Support:** Implement a full CLI supporting `--connect`, `--width`, `--height`, `--fps`, `--tcp`, `--headless`, `--duration`, and `--stats-interval`. Support statistics printing (network FPS, loss %, NACK recoveries, decode FPS, average frame age) every second, JSON summary at exit, and target-based exit codes.
*   **F2. Synthetic Soak Test Sender & Script:** Create a `phonecam-soak-sender` test tool in C++ that emulates the camera control/media protocol (RTP/UDP, NACK, PLI) and streams a pre-encoded 4K60 HEVC file loop. Add a bash script (`scripts/soak_4k60.sh`) that runs receiver and sender under clean and 2% loss conditions, validating targets.
*   **F3. Windows Receiver Migration:** Migrate `desktop/windows` to use the shared `phonecam-core` library. Promote auto-discovery into `desktop/core/discovery.*`. Extract legacy RTSP FFmpeg ingest to `desktop/windows/src/rtsp_ingest.*`. Implement a D3D11VA hwaccel decode backend in the FFmpeg decoding loop. Share the `FrameSink` pipeline and ensure matching CLI arguments.
*   **F4. Verification Report Alignment:** Clean up fictitious commands in `docs/verification-4k60.md`, replacing them with exact, copy-pasteable instructions, and paste the actual measured performance numbers from the soak test.

---

## 2. Architecture & Components

```mermaid
graph TD
    subgraph Shared Core (desktop/core)
        phonecam-core[phonecam-core Library]
        discovery[Discovery Protocol: discovery.h/cpp]
        client[PhoneCamClient]
        depacketizer[RtpHevcDepacketizer]
        control_parser[Control Parser]
    end

    subgraph macOS Target (desktop/macos)
        main_mm[main.mm: macOS Receiver]
        vt_dec[VideoToolbox Decoder]
        preview_mac[Cocoa Preview Layer / Null Sink]
    end

    subgraph Windows Target (desktop/windows)
        main_win[main.cpp: Windows Receiver]
        rtsp_ingest[rtsp_ingest.cpp/h: RTSP Mode Module]
        ffmpeg_dec[FFmpeg Decoder with D3D11VA hwaccel]
        frame_sinks[FrameSink Stack: Preview/Softcam/NullSinks]
    end

    subgraph Test Suite (desktop/tests)
        soak_sender[phonecam-soak-sender: Soak Test Sender]
        conformance[conformance-tests]
    end

    main_mm --> client
    main_win --> client
    main_win --> rtsp_ingest
    main_win --> discovery
    soak_sender --> control_parser
```

### 2.1 Shared Discovery Layer (`desktop/core/discovery.h` / `.cpp`)
*   **Purpose:** Shares the UDP auto-discovery beacon parsing, target resolution, and pair-code matching between Windows and macOS targets.
*   **Implementation:**
    *   Expose `class PhoneCamDiscovery` with `runDiscovery` and helper socket functions.
    *   Use `#ifdef _WIN32` for Windows Winsock and standard POSIX sockets for macOS.
    *   Include discovery self-tests in CTest.

### 2.2 macOS Receiver CLI (`desktop/macos/src/main.mm`)
*   **Command Line Options:**
    *   `--connect <host>`: Host to connect to (default: `127.0.0.1`).
    *   `--width <w>`, `--height <h>`: Resolution settings (default: 3840x2160).
    *   `--fps <fps>`: Frame rate setting (default: 60).
    *   `--tcp`: Enable TCP transport fallback.
    *   `--headless`: Disable Cocoa windows and run a pure command-line loop.
    *   `--duration <s>`: Seconds to run before exiting (default: infinite/negative).
    *   `--stats-interval <sec>`: Interval to print statistics (default: 1.0s).
*   **Execution Flow (Headless vs. GUI):**
    *   If `--headless` is provided: Do not call `NSApplicationMain`. Instantiate `phonecam::PhoneCamClient` and decode frames asynchronously using `VideoToolboxDecoder` to a null sink (deallocate decoded buffers). Run a sleep/wait loop on the main thread, capturing `SIGINT`.
    *   If running GUI: Boot the normal Cocoa `AppDelegate` window, configuring it with the CLI options.
*   **Stats Loop:**
    *   Every `--stats-interval` seconds, call `client_->getStats()` to retrieve the `ClientStats`.
    *   Format output to stdout:
        `[Stats] Net FPS: 59.8 | Loss: 0.12% | NACK: 5 | Decode FPS: 59.5 | Frame Age: 12.3 ms`
    *   At shutdown (duration reached or SIGINT received), print a single JSON line to stdout:
        `{"duration_sec": 60.0, "total_packets": 12345, "loss_percent": 0.0, "nack_recoveries": 10, "avg_network_fps": 59.9, "avg_decode_fps": 59.8, "avg_frame_age_ms": 15.2, "success": true}`
    *   Exit with code `1` if overall `avg_decode_fps` is `< 55.0` (when target FPS is 60) or `loss_percent` is `>= 1.0%`. Otherwise exit with `0`.

### 2.3 Synthetic Soak Test Sender (`desktop/tests/phonecam_soak_sender.cpp`)
*   **Handshake/Control:**
    *   Listen on UDP port 47822 for `"type":"connect"`. Respond with `"type":"connect_ack"` success JSON.
    *   Wait for `"type":"start"` to begin streaming.
    *   Respond to `"type":"ping"` with `"type":"pong"`.
    *   Handle `"type":"feedback"` by optionally logging.
    *   Handle `"type":"pli"` by logging.
*   **Retransmission Buffer & NACK:**
    *   Keep a 512-packet history buffer.
    *   Listen on UDP port 47822 for `"type":"nack"`. Parse sequence numbers from `seqs` array.
    *   Locate the requested packets in the history buffer and resend them to the target media socket.
*   **Streaming Loop:**
    *   Load pre-encoded 4K60 HEVC stream file.
    *   Packetize each HEVC frame into RTP packets (standard RFC 7798 payload format, using FUs for packets larger than 1400 bytes).
    *   Support `--inject-loss <pct>` to randomly discard packets before transmission.

### 2.4 Windows Receiver Target (`desktop/windows/src/`)
*   **Command Line Options:** Identical to F1.
*   **Decoder:** FFmpeg-based decoding.
    *   When running on Windows (`_WIN32`), configure D3D11VA hwaccel context using `av_hwdevice_ctx_create` with `AV_HWDEVICE_TYPE_D3D11VA`.
    *   Transfer decoded hardware frames to CPU memory using `av_hwframe_transfer_data`.
    *   Fall back gracefully to CPU HEVC decoding if D3D11VA initialization fails.
*   **Ingest Modes:**
    *   `--connect` (default): core UDP/TCP client path.
    *   `--rtsp`: runs the legacy FFmpeg RTSP pull extracted into `rtsp_ingest.cpp`.
*   **Sinks:** Feeds the same FrameSink pipeline, removing any Cocoa preview logic in the Windows target.

---

## 3. Data Flow

### 3.1 Control Handshake
```
Receiver                                          Sender (Soak Sender)
   |                                                        |
   | --- Connect JSON (UDP 47822) ------------------------> |
   | <--- Connect Ack JSON (UDP 47822) -------------------- |
   | --- Start JSON (UDP 47822) --------------------------> | (Streaming starts)
```

### 3.2 Media & Retransmission
```
Receiver                                          Sender (Soak Sender)
   |                                                        |
   | <--- RTP/UDP Media Packet (Seq N) -------------------- | (Store packet in history)
   | (Packet N+1 Lost)                                      |
   | <--- RTP/UDP Media Packet (Seq N+2) ------------------ | (Store packet in history)
   | (Detect Gap: N+1 missing)                              |
   | --- NACK JSON for [N+1] (UDP 47822) -----------------> |
   |                                                        | (Fetch from history)
   | <--- Resent RTP/UDP Media Packet (Seq N+1) ----------- |
```

---

## 4. Test & Verification Plan

1.  **CTest Configuration:**
    *   Add `soak-tests` CTest entry running a short 10s headless receiver + soak sender with 2% loss.
2.  **Script Verification:**
    *   Implement `scripts/soak_4k60.sh` executing receiver + sender for 60 seconds twice (clean vs. 2% loss).
    *   Assert decode FPS >= 55 and post-NACK loss < 1%.
    *   Print clean results.
3.  **Cross-Platform Builds:**
    *   Compile-check Windows target on macOS.
    *   Build and run macOS tests, Android Gradle test/assemble, iOS tests.
