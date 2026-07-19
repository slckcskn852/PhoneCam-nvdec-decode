# PhoneCam 4K60 Rebuild Verification Report

This document details the verification results and testing procedures for the PhoneCam 4K60 HEVC rebuild, spanning unit/conformance tests, synthetic soak tests, and actual hardware verification.

---

## 1. Unit & Conformance Test Results

Verification of the 4K60 HEVC streaming implementation has been completed across Android, iOS, and macOS environments. All tests passed successfully.

### Android Unit Tests
* **Total Tests Passed:** 49 tests
* **Key Components Covered:**
  * `RtpHevcPacketizerTest`: Validates fragmentation (FU-A packets) and single NAL unit modes matching RFC 7798.
  * `Stream4kControllerTest`: Verifies the stateful Adaptive Bitrate (ABR) algorithm, ensuring stable adjustments within a 5-second observation window and 10% step increments based on packet loss and network jitter.

### Desktop macOS CTest
* **Test Target:** `conformance-tests`
* **Result:** `conformance-tests` passed successfully. Validates the integrity of the jitter buffer, NACK queue, control handshake, and multi-channel TCP multiplexer.

### iOS Simulator & Device Build Tests
* **iOS Simulator Unit Tests:** 15 tests passed (`** TEST SUCCEEDED **`).
* **iOS Device Target Build:** Compiled successfully (`** BUILD SUCCEEDED **`). Verifies VideoToolbox HEVC hardware acceleration configurations and standard RTP packetization.

---

## 2. Synthetic Soak Test Instructions

A synthetic soak test simulates high-bitrate 4K60 HEVC media ingestion on a local loopback interface. This test verifies that the playout pipeline, jitter buffer, and decoder can sustain real-time performance.

### Step 1: Compile the Desktop Binaries

#### macOS:
Make sure all targets are built with the correct target platform:
```bash
cmake -B build/macos -DPHONECAM_TARGET=macos
cmake --build build/macos
```

#### Windows:
Compile the receiver binary using CMake (ensure the target platform is set to `windows` and the path to FFmpeg is specified):
```cmd
cmake -B build/windows -DPHONECAM_TARGET=windows -DFFMPEG_ROOT=C:/path/to/ffmpeg
cmake --build build/windows --config Release
```

### Step 2: Generate the HEVC Video Loop
Use FFmpeg to generate a 4K60 test video file (HEVC) of 5 seconds duration (which is automatically looped by the soak test sender):
```bash
ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=60 -c:v hevc_videotoolbox -b:v 35M -t 5 -pix_fmt yuv420p -an build/macos/test_4k60.hevc -y
```

### Step 3: Run the Soak Test Suite
The automated soak test runs clean and 2% loss-injection tests sequentially. Run it via CTest:
```bash
ctest --test-dir build/macos --output-on-failure
```

Or run the harness script directly:
```bash
./scripts/soak_4k60.sh --duration 60
```

### Measured Loopback Performance
The synthetic soak tests were verified on an Apple M-series macOS machine:

| Metric | Clean Channel (0% Loss) | Lossy Channel (2% Loss) | Target | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Duration** | 60.1 s | 60.0 s | $\ge$ 60.0 s | **PASSED** |
| **Average Decode FPS** | **59.4 fps** | **59.5 fps** | $\ge$ 55.0 fps | **PASSED** |
| **Post-NACK Loss %** | **0.00%** | **0.00%** | $< 1.0\%$ | **PASSED** |
| **Avg Frame Age** | 0.0 ms | 0.3 ms | $< 100$ ms | **PASSED** |
| **NACK Recoveries** | 0 | 3,900 | - | **PASSED** |

> [!NOTE]
> The post-NACK loss rate of **0.00%** under 2.0% injected network packet loss over a full 60-second duration confirms that the sequence wrap-safe NACK retransmission history (65536-packet ring buffer) and dynamic retry-bounded jitter buffer recovery pipeline successfully recovered 100% of all dropped media packets without any stream collapse.

---

## 3. Actual Hardware Verification Procedures

These instructions detail how to perform verification using a physical phone sender (Android/iOS) and a macOS/Windows receiver.

### Scenario A: WiFi UDP Mode
This mode uses RTP/UDP for high-performance wireless media transport and a separate UDP control channel.

1. **Configure the Phone App:**
   - Open the PhoneCam app on the Android/iOS device.
   - Select the **4K60 UDP** profile (toggle `Start 4K60 UDP` button).
   - Enter your computer's (Mac/Windows) IP address in the configuration field.
   - Tap **Start 4K60 UDP**.
2. **Launch the Receiver:**
   - Identify the phone's IP address on the local network (typically shown in the app interface).
   - Run the receiver on the computer, specifying the phone's IP address:
     ```bash
     ./build/macos/macos/phonecam-receiver --connect <android_ip>
     ```
3. **Verify Stream:**
   - Confirm the live video renders smoothly on the receiver preview.
   - Monitor the control channel outputs for ABR feedback updates.

### Scenario B: USB TCP Mode (Wired Fallback)
This mode forwards control and media over a single multiplexed TCP connection via a USB cable.

1. **Connect and Configure Port Forwarding:**
   - Connect the phone to the computer via a USB cable.
   - Enable USB Debugging on the Android device.
   - Forward the control and media port over ADB:
     ```bash
     adb forward tcp:47822 tcp:47822
     ```
2. **Start Phone Stream:**
   - Open the PhoneCam app on the phone.
   - Set the transport mode to **USB/TCP**.
   - Tap **Start 4K60 UDP**.
3. **Launch the Receiver:**
   - Start the receiver on the computer in TCP mode, targeting localhost (which ADB forwards to the phone):
     ```bash
     ./build/macos/macos/phonecam-receiver --connect 127.0.0.1 --tcp
     ```
4. **Verify Stream:**
   - Confirm the preview displays with minimal latency and zero NACK packets (as TCP is lossless).

---

## 4. Windows PC Hardware Verification Results

### Environment Setup
- **Sender Device:** Samsung Galaxy Z Fold 5 (Android 14, model/device `RFCW70YEQ1R`).
- **Receiver PC:** Windows 10/11 x64 PC with Visual Studio 2022 (MSVC 19.44.35228.0) and FFmpeg dependencies from vcpkg.
- **Virtual Camera:** Branded `PhoneCam Virtual Camera` DirectShow filter compiled from tshino/softcam and registered via UAC.

### Test Execution & Findings
1. **APK Clean Install:**
   - Compiled a fresh debug build of the Android app via Gradle on Windows.
   - Cleared conflicting developer signatures from previous iterations by performing an ADB uninstall (`com.phonecam`), then installed the new build (`app-debug.apk`).
2. **Direct Connection Test:**
   - The phone's local network IP was resolved to `192.168.1.220` with the receiver PC running at `192.168.1.125`.
   - Opened Windows Defender Firewall ports for the receiver using the provided `Install-PhoneCamFirewallRules.ps1` script.
   - Executed the receiver manually via:
     ```powershell
     .\build\windows-receiver\windows\Release\phonecam-receiver.exe --rtsp rtsp://192.168.1.220/
     ```
   - Stream rendering was confirmed fully functional on the Windows host with frames successfully sinking into the registered virtual webcam.

### Technical Analysis: FPS & Resolution Mitigation
- **Observation 1 (720p @ 30 FPS):** The initial receiver log reported a stable, average decode speed of `29.55 fps` (approximately 30 fps) at `1280x720` resolution.
- **Root Cause (720p Cap):**
  1. The Windows receiver options parser defaulted `--fps` to `30.0f` if the option was not explicitly provided on the command line.
  2. The target resolution in the client start function (`client.start(1280, 720, ...)`) was hardcoded to `1280, 720` in the Windows-specific launcher wrapper `desktop/windows/src/main.cpp`, preventing negotiated 4K (3840x2160) streaming requests to the Android encoder.
- **Remediation & Fixes Applied:**
  - Patched the Windows receiver launcher to accept custom `--width` and `--height` CLI flags.
  - Patched the auto-discovery callback (`applyDiscoveredDevice`) to dynamically extract the device's advertised encoding resolution (`width` and `height`) and target framerate (`fps`) from UDP discovery beacons, eliminating hardcoding during LAN auto-pairing.
- **Observation 2 (4K @ 60 FPS):**
  - When executing the patched receiver at full 4K60 resolution:
    ```powershell
    .\build\windows-receiver\windows\Release\phonecam-receiver.exe --rtsp rtsp://192.168.1.220/ --fps 60 --width 3840 --height 2160
    ```
  - The actual decode frame rate dropped significantly, averaging **`18.94 fps`** (693 frames decoded) with laggy rendering.
- **Performance Bottleneck Analysis:**
  1. **CPU Decoding Bottleneck:** The current receiver implementation utilizes standard software HEVC decoding on the host CPU. Processing a 4K HEVC stream (8.3 million pixels per frame) is highly CPU-intensive.
  2. **Software Color Space Conversion:** The decoded YUV420p frames are converted to BGR24 in software using FFmpeg's `sws_scale` function. Performing software scaling/pixel conversion on 4K frames at 60 fps creates a severe CPU pipeline bottleneck, leading to massive frame drops.
- **Recommendation for Fable 5:**
  - The software pipeline is verified functional on Windows, but CPU-bound software decoding and scaling cannot sustain 4K60 real-time playback.
  - To support actual 4K60, the Windows receiver must integrate GPU-based hardware decoding (such as **D3D11VA** or **NVDEC**) and GPU-based color conversion to offload the pipeline from the host CPU.


